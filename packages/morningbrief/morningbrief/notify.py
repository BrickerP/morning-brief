from __future__ import annotations

from morningbrief.proc import run_cmd


def notify(title: str, message: str) -> None:
    # Best-effort macOS notification; ignore failures.
    script = f'display notification "{_escape(message)}" with title "{_escape(title)}"'
    run_cmd(["osascript", "-e", script], timeout_s=10)


def _escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')
