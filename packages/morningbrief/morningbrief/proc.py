from __future__ import annotations

import os
import signal
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


def run_cancellable(
    args: Sequence[str],
    *,
    timeout_s: int,
    env: dict[str, str] | None = None,
) -> ProcResult:
    """Run a subprocess that is killed as a whole process group on SIGTERM/SIGINT.

    Long agent calls (session analysis, brief synthesis) are grandchildren of the
    menu-bar app: ``Swift Process → briefctl(python) → agent CLI``. When the app
    terminates briefctl, the plain ``run_cmd`` leaves the ``agent`` grandchild
    orphaned and still burning tokens. Here we start the child in its own session
    (``start_new_session=True``) and, on receiving SIGTERM/SIGINT, kill the entire
    group before exiting — so the grandchild dies with us.

    Must be called on the main thread (``signal.signal`` is main-thread only). The
    only callers are the assistant/synth agent invocations, which run on the main
    thread after any fetch thread-pool has joined.
    """
    try:
        proc = subprocess.Popen(
            list(args),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            start_new_session=True,
        )
    except FileNotFoundError as e:
        return ProcResult(127, "", str(e))

    def _kill_group(sig: int) -> None:
        try:
            os.killpg(os.getpgid(proc.pid), sig)
        except (ProcessLookupError, PermissionError, OSError):
            pass

    def _on_signal(signum, _frame):  # noqa: ANN001
        _kill_group(signal.SIGTERM)
        # Break out of communicate() so the finally-blocks up the stack (temp-dir
        # cleanup, lock release) run before we exit.
        raise KeyboardInterrupt

    # Install handlers on the main thread only; signal.signal raises ValueError
    # elsewhere, in which case we proceed without the group-kill safety net.
    previous: dict[int, object] = {}
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            previous[sig] = signal.getsignal(sig)
            signal.signal(sig, _on_signal)
        except (ValueError, OSError):
            previous.pop(sig, None)

    try:
        try:
            stdout, stderr = proc.communicate(timeout=timeout_s)
            return ProcResult(proc.returncode, stdout or "", stderr or "")
        except subprocess.TimeoutExpired as e:
            _kill_group(signal.SIGKILL)
            proc.wait()
            return ProcResult(
                124,
                e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or ""),
                f"timeout after {timeout_s}s: {e.stderr or ''}",
            )
        except KeyboardInterrupt:
            _kill_group(signal.SIGKILL)
            proc.wait()
            raise SystemExit(130)
    finally:
        for sig, handler in previous.items():
            try:
                signal.signal(sig, handler)  # type: ignore[arg-type]
            except (ValueError, OSError):
                pass
