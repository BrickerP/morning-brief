from __future__ import annotations

from morningbrief.adapters.ai_daily import fetch_ai_daily
from morningbrief.adapters.daily_read import fetch_daily_read
from morningbrief.adapters.dating import fetch_dating
from morningbrief.adapters.fs_street import fetch_fs_street
from morningbrief.config import SourceConfig
from morningbrief.models import SourceResult

ADAPTERS = {
    "ai_daily": fetch_ai_daily,
    "fs_street": fetch_fs_street,
    "daily_read": fetch_daily_read,
    "dating": fetch_dating,
}


def fetch_source(cfg: SourceConfig, *, local_date: str, python_bin: str) -> SourceResult:
    fn = ADAPTERS.get(cfg.id)
    if fn is None:
        from morningbrief.models import ErrorInfo

        return SourceResult(
            id=cfg.id,
            title=cfg.title,
            status="failed",
            error=ErrorInfo("unknown_adapter", f"No adapter for {cfg.id}"),
            meta={"fetched_at": "", "duration_ms": 0, "adapter_version": "0.1.0"},
        )
    return fn(cfg, local_date=local_date, python_bin=python_bin)
