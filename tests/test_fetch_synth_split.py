"""Tests for the fetch/synth split, disk reconstruction, and hash-skip caching.

The agent is always stubbed — these never call the real synthesis binary.
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

from morningbrief.config import AppConfig, SourceConfig
from morningbrief.models import BriefSection, ChildStatus, ErrorInfo, SourceResult
from morningbrief.pipeline import (
    compute_items_hash,
    load_sources_from_disk,
    run_pipeline,
    synth_brief,
)


def _redirect_paths(tmp_path: Path, monkeypatch) -> Path:
    import morningbrief.paths as paths
    import morningbrief.pipeline as pipeline

    monkeypatch.setattr(paths, "APP_SUPPORT", tmp_path / "as")
    monkeypatch.setattr(paths, "BRIEFS_DIR", tmp_path / "as" / "briefs")
    monkeypatch.setattr(paths, "LOGS_DIR", tmp_path / "as" / "logs")
    monkeypatch.setattr(paths, "AGENT_WS_DIR", tmp_path / "as" / "agent-workspaces")
    monkeypatch.setattr(pipeline, "brief_dir", lambda d: paths.BRIEFS_DIR / d)
    return paths.BRIEFS_DIR


def _ok(sid: str, title: str) -> SourceResult:
    return SourceResult(
        id=sid,
        title=title,
        status="ok",
        items=[{"kind": "article", "title": f"{title} item", "link": "https://example.com", "summary": "hi"}],
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )


def _cfg(**kw) -> AppConfig:
    base = dict(
        timezone="Asia/Shanghai",
        notify_on_degraded=False,
        sources=[SourceConfig(id="ai_daily", title="AI", skill_script="/dev/null")],
    )
    base.update(kw)
    return AppConfig(**base)


def _agent_sections() -> list[BriefSection]:
    return [
        BriefSection(
            id="ai_daily",
            title="AI",
            kind="news",
            body_md="synthesized body",
            source_ids=["ai_daily"],
            status="synthesized",
        ),
        BriefSection(
            id="tools",
            title="有趣的 AI 工具",
            kind="tools",
            body_md="tool one, tool two",
            source_ids=[],
            status="synthesized",
        ),
    ]


# --- 1. Disk reconstruct fidelity ------------------------------------------------


def test_source_result_from_dict_roundtrip():
    sr = SourceResult(
        id="daily_read",
        title="科技早读",
        status="partial",
        items=[{"title": "a", "link": "x"}, {"title": "b"}],
        children=[
            ChildStatus(id="noahpinion", status="ok", item_count=2),
            ChildStatus(id="stratechery", status="failed", item_count=0, error=ErrorInfo("net", "down")),
        ],
        error=None,
        meta={"fetched_at": "t", "duration_ms": 9, "adapter_version": "0.1.0"},
    )
    assert SourceResult.from_dict(sr.to_dict()).to_dict() == sr.to_dict()

    failed = SourceResult(
        id="ai_daily",
        title="AI",
        status="failed",
        error=ErrorInfo("adapter_exception", "boom"),
        meta={"fetched_at": "t", "duration_ms": 0, "adapter_version": "0.1.0"},
    )
    assert SourceResult.from_dict(failed.to_dict()).to_dict() == failed.to_dict()


def test_load_sources_from_disk_matches_payloads(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    day_dir = briefs / "2026-07-21"
    (day_dir / "sources").mkdir(parents=True)

    originals = {
        "ai_daily": _ok("ai_daily", "AI").to_dict(),
        "daily_read": SourceResult(
            id="daily_read",
            title="Read",
            status="partial",
            items=[{"title": "x"}],
            children=[ChildStatus(id="c", status="ok", item_count=1)],
            meta={"fetched_at": "t", "duration_ms": 3, "adapter_version": "0.1.0"},
        ).to_dict(),
    }
    for sid, payload in originals.items():
        clean = dict(payload)
        if clean.get("children") is None:
            clean.pop("children", None)
        (day_dir / "sources" / f"{sid}.json").write_text(
            json.dumps(clean, ensure_ascii=False), encoding="utf-8"
        )

    results = load_sources_from_disk(day_dir)
    reconstructed = {r.id: r.to_dict() for r in results}
    assert reconstructed["ai_daily"] == originals["ai_daily"]
    assert reconstructed["daily_read"] == originals["daily_read"]


def test_items_hash_ignores_meta():
    a = _ok("ai_daily", "AI")
    b = _ok("ai_daily", "AI")
    b.meta = {"fetched_at": "other", "duration_ms": 999, "adapter_version": "9"}
    assert compute_items_hash([a]) == compute_items_hash([b])


def test_items_hash_incorporates_status():
    # Same id + same (empty) items but different status must not collide.
    empty = SourceResult(
        id="ai_daily",
        title="AI",
        status="empty",
        items=[],
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )
    failed = SourceResult(
        id="ai_daily",
        title="AI",
        status="failed",
        items=[],
        error=ErrorInfo("net", "offline"),
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )
    assert compute_items_hash([empty]) != compute_items_hash([failed])


# --- 2. Hash-skip caching --------------------------------------------------------


def test_hash_skip_reuses_prior_agent_brief(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg()

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731

    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth:
        synth.return_value = (_agent_sections(), None)
        run_pipeline(date="2026-07-20", config=cfg)
        assert synth.call_count == 1

        # Same items on a later day → should reuse prior sections without calling the agent.
        synth.reset_mock()
        run_pipeline(date="2026-07-21", config=cfg)
        assert synth.call_count == 0

    day2 = briefs / "2026-07-21"
    brief = json.loads((day2 / "brief.json").read_text(encoding="utf-8"))
    assert brief["meta"]["synth"] == "cached"
    assert any(s["body_md"] == "synthesized body" for s in brief["sections"])


def test_same_day_second_run_reuses_agent_brief(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg()

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731

    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth:
        synth.return_value = (_agent_sections(), None)
        run_pipeline(date="2026-07-21", config=cfg)
        assert synth.call_count == 1

        # A second run on the *same* day with identical items must hit the cache,
        # even though the first run's run.json was overwritten at the start.
        synth.reset_mock()
        run_pipeline(date="2026-07-21", config=cfg)
        assert synth.call_count == 0

    brief = json.loads((briefs / "2026-07-21" / "brief.json").read_text(encoding="utf-8"))
    assert brief["meta"]["synth"] == "cached"
    assert any(s["body_md"] == "synthesized body" for s in brief["sections"])


def test_prior_degraded_not_cached(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg()

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731

    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth:
        # First run synthesis fails → degraded brief on disk.
        synth.return_value = (None, "boom")
        run_pipeline(date="2026-07-20", config=cfg)
        assert synth.call_count == 1

        # Same items next day, but prior is degraded → must live-synthesize, not cache.
        synth.reset_mock()
        synth.return_value = (_agent_sections(), None)
        run_pipeline(date="2026-07-21", config=cfg)
        assert synth.call_count == 1

    brief = json.loads((briefs / "2026-07-21" / "brief.json").read_text(encoding="utf-8"))
    assert brief["meta"]["synth"] == "agent"


def test_prior_skipped_never_becomes_cached(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg()

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731

    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth:
        synth.return_value = (_agent_sections(), None)
        # Previous day was skip-synth → meta.synth == "skipped".
        run_pipeline(date="2026-07-20", config=cfg, skip_synth=True)
        assert synth.call_count == 0

        # Same items but prior is "skipped": must live-synthesize, not cache.
        run_pipeline(date="2026-07-21", config=cfg, skip_synth=False)
        assert synth.call_count == 1

    day2 = briefs / "2026-07-21"
    brief = json.loads((day2 / "brief.json").read_text(encoding="utf-8"))
    assert brief["meta"]["synth"] == "agent"


# --- 3. skip-synth -> skipped ----------------------------------------------------


def test_skip_synth_sets_skipped(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg()

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731
    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth:
        run_pipeline(date="2026-07-21", config=cfg, skip_synth=True)
        assert synth.call_count == 0

    brief = json.loads((briefs / "2026-07-21" / "brief.json").read_text(encoding="utf-8"))
    assert brief["meta"]["synth"] == "skipped"


# --- 4. briefctl synth from disk -------------------------------------------------


def test_synth_brief_from_disk(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg()

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731
    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth:
        # Fetch-only run leaves sources/*.json on disk.
        run_pipeline(date="2026-07-21", config=cfg, skip_synth=True)
        assert synth.call_count == 0

        synth.return_value = (_agent_sections(), None)
        state = synth_brief(date="2026-07-21", config=cfg)
        assert synth.call_count == 1

    assert state is not None
    assert state["status"] == "ready"
    assert "items_hash" in state and "run_at" in state
    brief = json.loads((briefs / "2026-07-21" / "brief.json").read_text(encoding="utf-8"))
    assert brief["meta"]["synth"] == "agent"
    assert any(s["body_md"] == "synthesized body" for s in brief["sections"])


def test_synth_brief_missing_sources_returns_none(tmp_path: Path, monkeypatch):
    _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg()
    # No day dir / no sources at all.
    assert synth_brief(date="2026-07-21", config=cfg) is None
