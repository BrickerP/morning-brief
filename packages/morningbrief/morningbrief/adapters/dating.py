from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed

from morningbrief.adapters.base import now_iso, run_script, timed
from morningbrief.config import SourceConfig
from morningbrief.models import ChildStatus, ErrorInfo, SourceResult, Status, rollup_status


def _fetch_cat(python_bin: str, script: str, city: str, when: str, cat: str, timeout_s: int):
    code, payload, stderr = run_script(python_bin, script, [city, when, cat], timeout_s)
    return cat, code, payload, stderr


def fetch_dating(cfg: SourceConfig, *, local_date: str, python_bin: str) -> SourceResult:
    _, ms = timed()
    city = cfg.city or "beijing"
    when = cfg.when or "week"
    cats = cfg.categories or [
        "music",
        "drama",
        "commonweal",
        "salon",
        "exhibition",
        "film",
        "party",
        "sports",
        "comedy",
    ]
    children: list[ChildStatus] = []
    items: list[dict] = []
    seen_urls: set[str] = set()
    invocations: list[dict] = []
    child_statuses: list[Status] = []

    with ThreadPoolExecutor(max_workers=min(9, len(cats))) as pool:
        futs = {
            pool.submit(_fetch_cat, python_bin, cfg.skill_script, city, when, cat, cfg.timeout_s): cat
            for cat in cats
        }
        for fut in as_completed(futs):
            cat, code, payload, stderr = fut.result()
            invocations.append({"cat": cat, "returncode": code, "stderr": (stderr or "")[:120]})
            events = payload if isinstance(payload, list) else []
            if code != 0 and not events:
                children.append(
                    ChildStatus(
                        id=cat,
                        status="failed",
                        item_count=0,
                        error=ErrorInfo("fetch_failed", stderr or "empty with non-zero exit"),
                    )
                )
                child_statuses.append("failed")
                continue
            if not events:
                children.append(ChildStatus(id=cat, status="empty", item_count=0))
                child_statuses.append("empty")
                continue
            count = 0
            for ev in events:
                start = ev.get("start_time") or ""
                # Drop clearly past events (compare date prefix YYYY-MM-DD).
                if start and start[:10] < local_date:
                    continue
                url = ev.get("url") or ""
                if url and url in seen_urls:
                    continue
                if url:
                    seen_urls.add(url)
                items.append(
                    {
                        "kind": "event",
                        "category": cat,
                        "title": ev.get("title", ""),
                        "url": url,
                        "start_time": start,
                        "end_time": ev.get("end_time", ""),
                        "district": ev.get("district", ""),
                        "venue": ev.get("venue", ""),
                    }
                )
                count += 1
            children.append(ChildStatus(id=cat, status="ok", item_count=count))
            child_statuses.append("ok")

    status = rollup_status(child_statuses)
    # Sort events by start_time
    items.sort(key=lambda x: x.get("start_time") or "")
    return SourceResult(
        id=cfg.id,
        title=cfg.title,
        status=status,
        items=items[:80],
        children=sorted(children, key=lambda c: c.id),
        error=ErrorInfo("all_failed", "All dating categories failed") if status == "failed" else None,
        meta={
            "fetched_at": now_iso(),
            "duration_ms": ms(),
            "adapter_version": "0.1.0",
            "parse_mode": "json",
            "invocations": invocations,
            "city": city,
            "when": when,
            "local_date": local_date,
            "note": "Douban-only v1; WebSearch enrichment deferred",
        },
    )
