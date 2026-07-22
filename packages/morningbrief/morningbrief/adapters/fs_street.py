from __future__ import annotations

from morningbrief.adapters.base import now_iso, run_script, timed
from morningbrief.config import SourceConfig
from morningbrief.models import ErrorInfo, SourceResult


def fetch_fs_street(cfg: SourceConfig, *, local_date: str, python_bin: str) -> SourceResult:
    _, ms = timed()
    script = cfg.skill_script
    # Single fetch: the skill downloads the feed once and returns every public
    # entry in the lookback window (newest-first, members-only filtered), instead
    # of the adapter re-invoking (and re-downloading) once per day walked.
    code, payload, stderr = run_script(
        python_bin,
        script,
        ["--within-days", str(cfg.max_lookback_days), "--as-of", local_date],
        cfg.timeout_s,
    )
    invocations = [{"cmd": "within-days", "returncode": code, "stderr": stderr[:200]}]

    if code != 0 or not isinstance(payload, dict):
        return SourceResult(
            id=cfg.id,
            title=cfg.title,
            status="failed",
            error=ErrorInfo("fetch_failed", f"fetch failed: {stderr[:200] or payload}"),
            meta={
                "fetched_at": now_iso(),
                "duration_ms": ms(),
                "adapter_version": "0.2.0",
                "invocations": invocations,
            },
        )

    candidates = payload.get("candidates") or []
    if candidates:
        top = candidates[0]
        item = {
            "kind": "article",
            "title": top.get("title", ""),
            "link": top.get("link", ""),
            "date": top.get("date", ""),
            "content": top.get("content", ""),
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
                "adapter_version": "0.2.0",
                "parse_mode": cfg.parse_mode,
                "invocations": invocations,
                "selected_date": top.get("date", ""),
                "window": payload.get("window"),
            },
        )

    return SourceResult(
        id=cfg.id,
        title=cfg.title,
        status="empty",
        error=ErrorInfo("exhausted", f"No public FS article within {cfg.max_lookback_days} days"),
        meta={
            "fetched_at": now_iso(),
            "duration_ms": ms(),
            "adapter_version": "0.2.0",
            "invocations": invocations,
        },
    )
