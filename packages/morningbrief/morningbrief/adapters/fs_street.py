from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from morningbrief.adapters.base import now_iso, run_script, timed
from morningbrief.config import SourceConfig
from morningbrief.models import ErrorInfo, SourceResult


def fetch_fs_street(cfg: SourceConfig, *, local_date: str, python_bin: str) -> SourceResult:
    _, ms = timed()
    script = cfg.skill_script
    invocations: list[dict] = []

    code, payload, stderr = run_script(python_bin, script, ["--date-range"], cfg.timeout_s)
    invocations.append({"cmd": "date-range", "returncode": code, "stderr": stderr[:200]})
    if not isinstance(payload, dict) or code != 0:
        return SourceResult(
            id=cfg.id,
            title=cfg.title,
            status="failed",
            error=ErrorInfo("fetch_failed", f"date-range failed: {stderr or payload}"),
            meta={
                "fetched_at": now_iso(),
                "duration_ms": ms(),
                "adapter_version": "0.1.0",
                "invocations": invocations,
            },
        )

    min_d = payload.get("min_date")
    max_d = payload.get("max_date")
    if not max_d:
        return SourceResult(
            id=cfg.id,
            title=cfg.title,
            status="empty",
            error=ErrorInfo("empty", "No FS dates available"),
            meta={
                "fetched_at": now_iso(),
                "duration_ms": ms(),
                "adapter_version": "0.1.0",
                "invocations": invocations,
            },
        )

    # Walk newest → older up to max_lookback_days, skip members-only.
    end = date.fromisoformat(max_d)
    start_bound = date.fromisoformat(local_date) - timedelta(days=cfg.max_lookback_days)
    if min_d:
        start_bound = max(start_bound, date.fromisoformat(min_d))

    cursor = end
    while cursor >= start_bound:
        d = cursor.isoformat()
        code, article, stderr = run_script(python_bin, script, ["--date", d], cfg.timeout_s)
        invocations.append({"date": d, "returncode": code})
        if isinstance(article, dict) and article.get("error") == "not_found":
            cursor -= timedelta(days=1)
            continue
        if isinstance(article, dict) and article.get("title"):
            is_members = bool(article.get("is_members_only")) or "[FS Members]" in article.get("title", "")
            if is_members:
                cursor -= timedelta(days=1)
                continue
            item = {
                "kind": "article",
                "title": article.get("title", ""),
                "link": article.get("link", ""),
                "date": d,
                "content": article.get("content", ""),
                "is_members_only": False,
            }
            return SourceResult(
                id=cfg.id,
                title=cfg.title,
                status="ok",
                items=[item],
                meta={
                    "fetched_at": now_iso(),
                    "duration_ms": ms(),
                    "adapter_version": "0.1.0",
                    "parse_mode": cfg.parse_mode,
                    "invocations": invocations,
                    "selected_date": d,
                },
            )
        cursor -= timedelta(days=1)

    return SourceResult(
        id=cfg.id,
        title=cfg.title,
        status="empty",
        error=ErrorInfo("exhausted", f"No public FS article within {cfg.max_lookback_days} days"),
        meta={
            "fetched_at": now_iso(),
            "duration_ms": ms(),
            "adapter_version": "0.1.0",
            "invocations": invocations,
        },
    )
