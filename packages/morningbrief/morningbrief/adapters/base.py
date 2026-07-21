from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from typing import Any, Callable

from morningbrief.models import ErrorInfo, SourceResult
from morningbrief.paths import resolve_python
from morningbrief.proc import run_cmd


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_json_stdout(stdout: str) -> Any:
    text = stdout.strip()
    if not text:
        return None
    return json.loads(text)


def run_script(
    python_bin: str,
    script: str,
    args: list[str],
    timeout_s: int,
) -> tuple[int, Any, str]:
    py = python_bin or resolve_python()
    result = run_cmd([py, script, *args], timeout_s=timeout_s)
    payload: Any = None
    if result.stdout.strip():
        try:
            payload = parse_json_stdout(result.stdout)
        except json.JSONDecodeError:
            payload = {"raw": result.stdout, "kind": "raw"}
    return result.returncode, payload, result.stderr


def timed() -> tuple[float, Callable[[], int]]:
    start = time.perf_counter()

    def ms() -> int:
        return int((time.perf_counter() - start) * 1000)

    return start, ms


def failed_result(source_id: str, title: str, code: str, message: str, duration_ms: int) -> SourceResult:
    return SourceResult(
        id=source_id,
        title=title,
        status="failed",
        error=ErrorInfo(code, message),
        meta={
            "fetched_at": now_iso(),
            "duration_ms": duration_ms,
            "adapter_version": "0.1.0",
        },
    )
