from __future__ import annotations

import subprocess
from dataclasses import dataclass
from typing import Sequence


@dataclass
class ProcResult:
    returncode: int
    stdout: str
    stderr: str


def run_cmd(
    args: Sequence[str],
    *,
    timeout_s: int,
    env: dict[str, str] | None = None,
) -> ProcResult:
    try:
        completed = subprocess.run(
            list(args),
            capture_output=True,
            text=True,
            timeout=timeout_s,
            env=env,
            check=False,
        )
        return ProcResult(completed.returncode, completed.stdout or "", completed.stderr or "")
    except subprocess.TimeoutExpired as e:
        return ProcResult(
            124,
            e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or ""),
            f"timeout after {timeout_s}s: {e.stderr or ''}",
        )
    except FileNotFoundError as e:
        return ProcResult(127, "", str(e))
