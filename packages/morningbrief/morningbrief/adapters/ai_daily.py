from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo

from morningbrief.adapters.base import failed_result, now_iso, run_script, timed
from morningbrief.config import SourceConfig
from morningbrief.models import ErrorInfo, SourceResult
from morningbrief.timeutil import date_str, lookback_dates, local_today


def fetch_ai_daily(cfg: SourceConfig, *, local_date: str, python_bin: str) -> SourceResult:
    _, ms = timed()
    script = cfg.skill_script
    # Probe lookback dates newest-first relative to user local day (not UTC relative flags).
    user_day = date.fromisoformat(local_date)
    candidates = lookback_dates(user_day, cfg.lookback_days)
    invocations: list[dict] = []

    for d in candidates:
        code, payload, stderr = run_script(python_bin, script, ["--date", d], cfg.timeout_s)
        invocations.append({"date": d, "returncode": code, "stderr": stderr[:200]})
        if isinstance(payload, dict) and payload.get("error") == "not_found":
            continue
        if isinstance(payload, dict) and "error" in payload and "title" not in payload:
            # network or other error — keep probing unless hard fail
            if code != 0:
                continue
        if isinstance(payload, dict) and payload.get("title"):
            item = {
                "kind": "article",
                "title": payload.get("title", ""),
                "link": payload.get("link", ""),
                "date": d,
                "content": payload.get("content", ""),
                "pubDate": payload.get("pubDate", ""),
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

    # Exhausted lookback
    status = "empty"
    err = ErrorInfo("not_found", f"No AI daily within lookback {cfg.lookback_days} days of {local_date}")
    # If last invocation was a hard network failure with empty probes
    if invocations and all(i.get("returncode") not in (0,) for i in invocations):
        status = "failed"
        err = ErrorInfo("fetch_failed", "All ai-daily invocations failed")

    return SourceResult(
        id=cfg.id,
        title=cfg.title,
        status=status,
        error=err if status != "ok" else None,
        items=[],
        meta={
            "fetched_at": now_iso(),
            "duration_ms": ms(),
            "adapter_version": "0.1.0",
            "parse_mode": cfg.parse_mode,
            "invocations": invocations,
        },
    )
