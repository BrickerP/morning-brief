from __future__ import annotations

import concurrent.futures
import hashlib
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from morningbrief.adapters import fetch_source
from morningbrief.atomic import atomic_write_json, atomic_write_text
from morningbrief.config import AppConfig, load_config
from morningbrief.lock import EXIT_LOCKED, acquire, release
from morningbrief.models import BriefDocument, BriefHero, BriefSection, ErrorInfo, SourceResult
from morningbrief.paths import brief_dir, ensure_app_dirs, resolve_python
from morningbrief.sections import ensure_hero, render_brief_md, source_to_section, tools_placeholder_section
from morningbrief.synth import synthesize
from morningbrief.timeutil import date_str, local_today
from morningbrief.validate import validate_brief_document, validate_run_state, validate_source_result
from morningbrief.notify import notify


def _now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def brief_meta(synth: str, cfg: AppConfig, **extra: Any) -> dict[str, Any]:
    return {
        "synth": synth,
        "staleness_hours": cfg.staleness_hours,
        "timezone": cfg.timezone,
        **extra,
    }


def compute_items_hash(results: list[SourceResult]) -> str:
    """Stable hash over each source's id, status, and items.

    Volatile meta (fetched_at/duration_ms/adapter_version) is excluded so a
    rerun with identical content still matches, but per-source status is
    included so empty vs failed can't collide into a stale cache.
    """
    payload = {r.id: {"status": r.status, "items": r.items} for r in results}
    canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def load_sources_from_disk(
    day_dir: Path, enabled: list[Any] | None = None
) -> list[SourceResult]:
    """Reconstruct SourceResult list from day_dir/sources/*.json with full fidelity."""
    sources_dir = day_dir / "sources"
    results: list[SourceResult] = []
    if not sources_dir.exists():
        return results
    for path in sorted(sources_dir.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        try:
            results.append(SourceResult.from_dict(data))
        except (KeyError, TypeError):
            continue
    if enabled:
        order = {s.id: i for i, s in enumerate(enabled)}
        results.sort(key=lambda r: order.get(r.id, 999))
    return results


def _build_local_sections(
    results: list[SourceResult], section_kinds: dict[str, str]
) -> list[BriefSection]:
    sections = [
        source_to_section(r, section_kinds.get(r.id, "digest"))
        for r in results
        if r.status != "failed"
    ]
    sections.extend(
        source_to_section(r, section_kinds.get(r.id, "digest"))
        for r in results
        if r.status == "failed"
    )
    return sections


def read_run_snapshot(day_dir: Path) -> tuple[Path, dict[str, Any]] | None:
    """Snapshot the existing run.json (with its day_dir) before it is overwritten.

    Lets a second same-day run still see the prior run's items_hash for caching,
    since the on-disk run.json is about to be clobbered by the new run.
    """
    run_path = day_dir / "run.json"
    if not run_path.exists():
        return None
    try:
        data = json.loads(run_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    return day_dir, data


def find_previous_run(
    briefs_root: Path,
    current_run_id: str,
    prev_snapshot: tuple[Path, dict[str, Any]] | None = None,
) -> tuple[Path, dict[str, Any]] | None:
    """Latest run.json across all days, excluding the current run, ordered by run_at/started_at.

    ``prev_snapshot`` (the pre-overwrite run.json for the current day) is added as
    an extra candidate so a same-day rerun can match the prior run even though its
    on-disk run.json has since been replaced by the current run.
    """
    candidates: list[tuple[str, Path, dict[str, Any]]] = []
    if briefs_root.exists():
        for run_path in briefs_root.glob("*/run.json"):
            try:
                data = json.loads(run_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                continue
            if data.get("run_id") == current_run_id:
                continue
            key = data.get("run_at") or data.get("started_at") or ""
            candidates.append((key, run_path.parent, data))
    if prev_snapshot is not None:
        snap_dir, snap_data = prev_snapshot
        if snap_data.get("run_id") != current_run_id:
            key = snap_data.get("run_at") or snap_data.get("started_at") or ""
            candidates.append((key, snap_dir, snap_data))
    if not candidates:
        return None
    candidates.sort(key=lambda t: t[0])
    _, day_dir, data = candidates[-1]
    return day_dir, data


def _cached_sections(prev_day_dir: Path) -> list[BriefSection] | None:
    """Prior brief.json sections iff it was a real agent synthesis with body content.

    Only trusts prior ``meta.synth == "agent"`` — degraded/skipped/fallback briefs
    must be re-synthesized rather than reused.
    """
    brief_path = prev_day_dir / "brief.json"
    if not brief_path.exists():
        return None
    try:
        data = json.loads(brief_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    synth = (data.get("meta") or {}).get("synth")
    if synth != "agent":
        return None
    sections_raw = data.get("sections") or []
    if not sections_raw:
        return None
    sections = [BriefSection.from_dict(s) for s in sections_raw]
    if not any(s.body_md.strip() for s in sections):
        return None
    return sections


def cached_sections_if_match(
    day_dir: Path,
    items_hash: str,
    current_run_id: str,
    prev_snapshot: tuple[Path, dict[str, Any]] | None = None,
) -> list[BriefSection] | None:
    """Return prior sections to reuse when the previous run has identical items_hash."""
    prev = find_previous_run(day_dir.parent, current_run_id, prev_snapshot)
    if prev is None:
        return None
    prev_day_dir, prev_run = prev
    if prev_run.get("items_hash") != items_hash:
        return None
    return _cached_sections(prev_day_dir)


def maybe_synthesize(
    cfg: AppConfig,
    day: str,
    results: list[SourceResult],
    section_kinds: dict[str, str],
    run_id: str,
    run_state: dict[str, Any],
    base_sections: list[BriefSection],
) -> tuple[list[BriefSection], dict[str, Any], str, BriefHero | None]:
    """Live synthesis; falls back to degraded local sections. Returns (sections, meta, status, hero)."""
    out = synthesize(cfg, day, results, section_kinds, run_id)
    synth_sections, synth_err = out[0], out[1]
    synth_hero = out[2] if len(out) > 2 else None
    run_state["agent_auth"] = synth_err != "agent_auth_failed"
    if synth_sections is not None:
        return synth_sections, brief_meta("agent", cfg), "ready", synth_hero

    sections = list(base_sections)
    if not any(s.id == "tools" for s in sections):
        sections.append(tools_placeholder_section())
    run_state["errors"].append(f"synth: {synth_err}")
    if cfg.notify_on_degraded:
        notify("Morning Brief", f"合成降级: {synth_err}")
    return sections, brief_meta("degraded", cfg, synth_error=synth_err), "degraded", None


def maybe_notify_ready(
    cfg: AppConfig,
    day: str,
    day_dir: Path,
    results: list[SourceResult],
    run_state: dict[str, Any],
    headline: str | None = None,
) -> None:
    """Notify once when a brief lands 'ready', if enabled. Dedups via run.json flag."""
    if not cfg.notify_on_ready:
        return
    if run_state.get("status") != "ready":
        return
    if run_state.get("notified_ready"):
        return
    # Persist the dedup flag before notifying so re-reads never double-fire.
    run_state["notified_ready"] = True
    atomic_write_json(day_dir / "run.json", run_state)
    degraded_sources = [r.id for r in results if r.status in ("failed", "empty")]
    clean_headline = (headline or "").strip()
    if clean_headline:
        if len(clean_headline) > 40:
            clean_headline = clean_headline[:39] + "…"
        message = f"早报已就绪 · {clean_headline}"
    else:
        message = f"{day} 早报已就绪"
    if degraded_sources:
        message += f"（部分来源异常: {', '.join(degraded_sources)}）"
    notify("Morning Brief", message)


_TERMINAL_RUN_STATUSES = {"ready", "degraded", "failed"}


def _has_terminal_run_state(day_dir: Path) -> bool:
    """True if run.json exists with a terminal status that must not be clobbered."""
    run_path = day_dir / "run.json"
    if not run_path.exists():
        return False
    try:
        data = json.loads(run_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return False
    return data.get("status") in _TERMINAL_RUN_STATUSES


def _acquire_lock_or_record_locked(day_dir: Path, lock_path: Path, run_id: str, day: str, cfg: AppConfig) -> None:
    """Acquire the run lock, recording a 'locked' run.json and re-raising if another run holds it."""
    try:
        acquire(lock_path, run_id, cfg.lock_ttl_s)
    except SystemExit as e:
        if e.code == EXIT_LOCKED and not _has_terminal_run_state(day_dir):
            # Only stamp a 'locked' stub when there's no completed brief to protect;
            # never clobber an existing terminal run.json (ready/degraded/failed).
            state = {
                "date": day,
                "run_id": run_id,
                "status": "locked",
                "started_at": _now(),
                "finished_at": _now(),
                "agent_auth": False,
                "sources": {},
                "errors": ["locked by live process"],
            }
            atomic_write_json(day_dir / "run.json", state)
        raise


def _finalize_run(
    day: str,
    day_dir: Path,
    cfg: AppConfig,
    results: list[SourceResult],
    run_state: dict[str, Any],
    brief_status: str,
    headline: str | None = None,
) -> dict[str, Any]:
    """Stamp final status/timestamps, validate, persist run.json, and fire the ready notification."""
    run_state["status"] = brief_status if brief_status in ("ready", "degraded", "failed") else "ready"
    finished = _now()
    run_state["finished_at"] = finished
    run_state["run_at"] = finished
    # Surface per-source fetch durations at the top level (the field was declared but never filled).
    run_state["timings_ms"] = {
        sid: info.get("duration_ms", 0) for sid, info in run_state.get("sources", {}).items()
    }
    try:
        validate_run_state(run_state)
    except Exception as exc:  # noqa: BLE001
        run_state["errors"].append(f"run schema: {exc}")
    atomic_write_json(day_dir / "run.json", run_state)
    maybe_notify_ready(cfg, day, day_dir, results, run_state, headline)
    return run_state


def _brief_headline(doc_dict: dict[str, Any] | None) -> str | None:
    """Pull the hero headline out of a written brief doc for the ready notification."""
    if not doc_dict:
        return None
    hero = doc_dict.get("hero")
    if isinstance(hero, dict):
        headline = hero.get("headline")
        if isinstance(headline, str) and headline.strip():
            return headline.strip()
    return None


def write_brief_from_results(
    day: str,
    day_dir: Path,
    cfg: AppConfig,
    results: list[SourceResult],
    section_kinds: dict[str, str],
    sections: list[BriefSection],
    meta: dict[str, Any],
    brief_status: str,
    run_state: dict[str, Any],
    existing_hero: BriefHero | None = None,
) -> tuple[dict[str, Any], str]:
    """Validate (with local fallback) and persist brief.md then brief.json. Returns (doc, status)."""
    doc = BriefDocument(
        date=day,
        generated_at=_now(),
        status=brief_status,  # type: ignore[arg-type]
        sections=sections,
        hero=ensure_hero(results, sections, existing_hero),
        meta=meta,
    )
    doc_dict = doc.to_dict()
    try:
        validate_brief_document(doc_dict)
    except Exception as exc:  # noqa: BLE001
        # Fall back to purely local sections if the shape is somehow invalid.
        run_state["errors"].append(f"brief schema: {exc}")
        fallback_sections = [
            source_to_section(r, section_kinds.get(r.id, "digest")) for r in results
        ] + [tools_placeholder_section()]
        doc = BriefDocument(
            date=day,
            generated_at=_now(),
            status="degraded",
            sections=fallback_sections,
            hero=ensure_hero(results, fallback_sections),
            meta=brief_meta("schema_fallback", cfg, error=str(exc)),
        )
        doc_dict = doc.to_dict()
        validate_brief_document(doc_dict)
        brief_status = "degraded"

    md = render_brief_md(day, doc.sections, doc.status)
    # Write body first, commit marker (brief.json) last.
    atomic_write_text(day_dir / "brief.md", md)
    atomic_write_json(day_dir / "brief.json", doc_dict)
    return doc_dict, brief_status


def run_pipeline(
    *,
    date: str | None = None,
    config: AppConfig | None = None,
    skip_synth: bool | None = None,
) -> dict[str, Any]:
    ensure_app_dirs()
    cfg = config or load_config()
    if skip_synth is not None:
        cfg.skip_synth = skip_synth

    day = date or date_str(local_today(cfg.timezone))
    day_dir = brief_dir(day)
    day_dir.mkdir(parents=True, exist_ok=True)
    (day_dir / "sources").mkdir(exist_ok=True)

    run_id = uuid.uuid4().hex[:12]
    lock_path = day_dir / "run.lock"
    _acquire_lock_or_record_locked(day_dir, lock_path, run_id, day, cfg)

    # Snapshot the prior run.json before we overwrite it so a second same-day run
    # with identical items can still match the previous run's items_hash.
    prev_snapshot = read_run_snapshot(day_dir)

    run_state: dict[str, Any] = {
        "date": day,
        "run_id": run_id,
        "status": "fetching",
        "started_at": _now(),
        "finished_at": None,
        "agent_auth": False,
        "sources": {},
        "errors": [],
        "timings_ms": {},
    }
    atomic_write_json(day_dir / "run.json", run_state)

    python_bin = resolve_python()
    enabled = [s for s in cfg.sources if s.enabled]
    results: list[SourceResult] = []
    section_kinds = {s.id: s.section_kind for s in enabled}

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(4, max(1, len(enabled)))) as pool:
            futs = {
                pool.submit(fetch_source, src, local_date=day, python_bin=python_bin): src
                for src in enabled
            }
            for fut in concurrent.futures.as_completed(futs):
                src = futs[fut]
                try:
                    result = fut.result()
                except Exception as exc:  # noqa: BLE001 — adapter boundary
                    result = SourceResult(
                        id=src.id,
                        title=src.title,
                        status="failed",
                        error=ErrorInfo("adapter_exception", str(exc)),
                        meta={"fetched_at": _now(), "duration_ms": 0, "adapter_version": "0.1.0"},
                    )
                results.append(result)
                payload = result.to_dict()
                if payload.get("children") is None:
                    payload.pop("children", None)
                try:
                    validate_source_result(payload)
                except Exception as exc:  # noqa: BLE001
                    run_state["errors"].append(f"schema {src.id}: {exc}")
                atomic_write_json(day_dir / "sources" / f"{src.id}.json", payload)
                run_state["sources"][src.id] = {
                    "status": result.status,
                    "duration_ms": result.meta.get("duration_ms", 0),
                    "error": result.error.to_dict() if result.error else None,
                }
                atomic_write_json(day_dir / "run.json", run_state)

        # Order results by config order
        order = {s.id: i for i, s in enumerate(enabled)}
        results.sort(key=lambda r: order.get(r.id, 999))

        local_sections = _build_local_sections(results, section_kinds)
        items_hash = compute_items_hash(results)
        run_state["items_hash"] = items_hash

        brief_status = "ready"
        sections: list[BriefSection] = local_sections
        meta: dict[str, Any] = brief_meta("none", cfg)
        agent_hero: BriefHero | None = None

        if cfg.skip_synth:
            # User opted out of synthesis: degraded local sections, never cached.
            brief_status = "degraded" if any(r.status == "failed" for r in results) else "ready"
            if not any(s.id == "tools" for s in sections):
                sections.append(tools_placeholder_section())
            meta = brief_meta("skipped", cfg)
        else:
            cached = cached_sections_if_match(day_dir, items_hash, run_id, prev_snapshot)
            if cached is not None:
                sections = cached
                meta = brief_meta("cached", cfg)
                brief_status = "ready"
            else:
                run_state["status"] = "synthesizing"
                atomic_write_json(day_dir / "run.json", run_state)
                sections, meta, brief_status, agent_hero = maybe_synthesize(
                    cfg, day, results, section_kinds, run_id, run_state, local_sections
                )

        if all(r.status == "failed" for r in results) and results:
            brief_status = "failed"

        doc_dict, brief_status = write_brief_from_results(
            day, day_dir, cfg, results, section_kinds, sections, meta, brief_status, run_state,
            existing_hero=agent_hero,
        )

        return _finalize_run(
            day, day_dir, cfg, results, run_state, brief_status,
            headline=_brief_headline(doc_dict),
        )
    finally:
        release(lock_path, run_id)


def synth_brief(
    *,
    date: str | None = None,
    config: AppConfig | None = None,
) -> dict[str, Any] | None:
    """Reconstruct sources from disk and (re)synthesize a brief. Returns None if no sources."""
    ensure_app_dirs()
    cfg = config or load_config()
    cfg.skip_synth = False

    day = date or date_str(local_today(cfg.timezone))
    day_dir = brief_dir(day)
    if not day_dir.exists():
        return None

    enabled = [s for s in cfg.sources if s.enabled]
    section_kinds = {s.id: s.section_kind for s in enabled}
    results = load_sources_from_disk(day_dir, enabled)
    if not results:
        return None

    run_id = uuid.uuid4().hex[:12]
    lock_path = day_dir / "run.lock"
    _acquire_lock_or_record_locked(day_dir, lock_path, run_id, day, cfg)

    started = _now()
    run_state: dict[str, Any] = {
        "date": day,
        "run_id": run_id,
        "status": "synthesizing",
        "started_at": started,
        "finished_at": None,
        "agent_auth": False,
        "sources": {
            r.id: {
                "status": r.status,
                "duration_ms": r.meta.get("duration_ms", 0),
                "error": r.error.to_dict() if r.error else None,
            }
            for r in results
        },
        "errors": [],
        "timings_ms": {},
        "items_hash": compute_items_hash(results),
    }
    atomic_write_json(day_dir / "run.json", run_state)

    try:
        local_sections = _build_local_sections(results, section_kinds)
        sections, meta, brief_status, agent_hero = maybe_synthesize(
            cfg, day, results, section_kinds, run_id, run_state, local_sections
        )
        if all(r.status == "failed" for r in results) and results:
            brief_status = "failed"

        doc_dict, brief_status = write_brief_from_results(
            day, day_dir, cfg, results, section_kinds, sections, meta, brief_status, run_state,
            existing_hero=agent_hero,
        )

        return _finalize_run(
            day, day_dir, cfg, results, run_state, brief_status,
            headline=_brief_headline(doc_dict),
        )
    finally:
        release(lock_path, run_id)
