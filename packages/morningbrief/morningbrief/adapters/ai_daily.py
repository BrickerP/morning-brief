from __future__ import annotations

from morningbrief.adapters.base import now_iso, run_script, timed
from morningbrief.config import SourceConfig
from morningbrief.models import ErrorInfo, SourceResult


def fetch_ai_daily(cfg: SourceConfig, *, local_date: str, python_bin: str) -> SourceResult:
    _, ms = timed()
    script = cfg.skill_script
    # Single fetch: the skill downloads the ~1MB feed once and returns every
    # candidate in the lookback window (newest-first), instead of the adapter
    # re-invoking (and re-downloading) once per probe day.
    code, payload, stderr = run_script(
        python_bin,
        script,
        ["--within-days", str(cfg.lookback_days), "--as-of", local_date],
        cfg.timeout_s,
    )
    invocations = [{"cmd": "within-days", "returncode": code, "stderr": stderr[:200]}]

    if code == 0 and isinstance(payload, dict):
        candidates = payload.get("candidates") or []
        if candidates:
            top = candidates[0]
            item = {
                "kind": "article",
                "title": top.get("title", ""),
                "link": top.get("link", ""),
                "date": top.get("date", ""),
                "content": top.get("content", ""),
                "pubDate": top.get("pubDate", ""),
            }
            return SourceResult(
                id=cfg.id,
                title=cfg.title,
                status="ok",
                items=[item],
                meta={
                    "fetched_at": now_iso(),
                    "duration_ms": ms(),
                    "adapter_version": "0.2.0",
                    "parse_mode": cfg.parse_mode,
                    "invocations": invocations,
                    "selected_date": top.get("date", ""),
                    "window": payload.get("window"),
                },
            )

    # No candidate in window, or a hard failure.
    status = "failed" if code != 0 else "empty"
    err = (
        ErrorInfo("fetch_failed", stderr[:200] or "ai-daily fetch failed")
        if code != 0
        else ErrorInfo("not_found", f"No AI daily within lookback {cfg.lookback_days} days of {local_date}")
    )
    return SourceResult(
        id=cfg.id,
        title=cfg.title,
        status=status,
        error=err,
        items=[],
        meta={
            "fetched_at": now_iso(),
            "duration_ms": ms(),
            "adapter_version": "0.2.0",
            "parse_mode": cfg.parse_mode,
            "invocations": invocations,
        },
    )
