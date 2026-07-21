from __future__ import annotations

from morningbrief.adapters.base import now_iso, run_script, timed
from morningbrief.config import SourceConfig
from morningbrief.models import ChildStatus, ErrorInfo, SourceResult, Status, rollup_status


def fetch_daily_read(cfg: SourceConfig, *, local_date: str, python_bin: str) -> SourceResult:
    _, ms = timed()
    days = max(1, cfg.lookback_days)
    code, payload, stderr = run_script(
        python_bin,
        cfg.skill_script,
        ["--days", str(days), "--format", "json"],
        cfg.timeout_s,
    )
    if code != 0 or not isinstance(payload, dict):
        return SourceResult(
            id=cfg.id,
            title=cfg.title,
            status="failed",
            error=ErrorInfo("fetch_failed", stderr or str(payload)),
            meta={
                "fetched_at": now_iso(),
                "duration_ms": ms(),
                "adapter_version": "0.1.0",
                "invocations": [{"returncode": code}],
            },
        )

    sources = payload.get("sources") or []
    children: list[ChildStatus] = []
    items: list[dict] = []
    child_statuses: list[Status] = []

    for src in sources:
        sid = src.get("source") or src.get("id") or "unknown"
        err = src.get("error")
        articles = src.get("articles") or []
        if err:
            st: Status = "failed" if not articles else "partial"
            children.append(
                ChildStatus(
                    id=sid,
                    status=st,
                    item_count=len(articles),
                    error=ErrorInfo("child_error", str(err)),
                )
            )
            child_statuses.append(st)
        elif not articles:
            children.append(ChildStatus(id=sid, status="empty", item_count=0))
            child_statuses.append("empty")
        else:
            children.append(ChildStatus(id=sid, status="ok", item_count=len(articles)))
            child_statuses.append("ok")
        for a in articles:
            items.append(
                {
                    "kind": "article",
                    "source": sid,
                    "title": a.get("title", ""),
                    "link": a.get("link", ""),
                    "date": a.get("published", ""),
                    "summary": a.get("summary", ""),
                }
            )

    status = rollup_status(child_statuses) if child_statuses else "empty"
    return SourceResult(
        id=cfg.id,
        title=cfg.title,
        status=status,
        items=items,
        children=children,
        error=None
        if status != "failed"
        else ErrorInfo("all_failed", "All daily-read child sources failed"),
        meta={
            "fetched_at": now_iso(),
            "duration_ms": ms(),
            "adapter_version": "0.1.0",
            "parse_mode": "json",
            "invocations": [{"returncode": code, "days": days}],
            "window": payload.get("window"),
        },
    )
