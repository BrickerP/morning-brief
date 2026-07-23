"""Process-group cancellation tests for run_cancellable.

Verifies that a SIGTERM to the briefctl process kills the whole process group —
so the `agent` grandchild dies with it instead of orphaning — and that the
KeyboardInterrupt unwind lets caller finally-blocks (temp-dir cleanup, lock
release) run before exit.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[1] / "packages" / "morningbrief"


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def test_run_cancellable_kills_grandchild_group_on_sigterm(tmp_path: Path) -> None:
    pidfile = tmp_path / "grandchild.pid"
    sentinel = tmp_path / "finally_ran"

    # Grandchild (stands in for the `agent` CLI): record its pid, then sleep long.
    grandchild = (
        "import time,sys;"
        "open(sys.argv[1],'w').write(str(__import__('os').getpid()));"
        "time.sleep(60)"
    )
    # Child launched by run_cancellable spawns the grandchild, then sleeps.
    child = (
        "import subprocess,sys,time;"
        f"gc=subprocess.Popen([sys.executable,'-c',{grandchild!r},sys.argv[1]]);"
        "time.sleep(60)"
    )

    # The "briefctl" layer: run_cancellable with a try/finally that must run on
    # the KeyboardInterrupt→SystemExit unwind.
    runner = f"""
import sys
sys.path.insert(0, {str(PACKAGE_ROOT)!r})
from morningbrief.proc import run_cancellable
try:
    run_cancellable([sys.executable, "-c", {child!r}, {str(pidfile)!r}], timeout_s=60)
finally:
    open({str(sentinel)!r}, "w").write("ran")
"""

    proc = subprocess.Popen([sys.executable, "-c", runner])
    try:
        gc_pid = None
        for _ in range(100):
            if pidfile.exists():
                try:
                    gc_pid = int(pidfile.read_text().strip())
                    break
                except ValueError:
                    pass
            time.sleep(0.1)
        assert gc_pid is not None, "grandchild never started"
        assert _alive(gc_pid)

        proc.terminate()  # SIGTERM, as Swift terminating briefctl would
        proc.wait(timeout=15)

        # SystemExit(130) from the KeyboardInterrupt path.
        assert proc.returncode == 130, f"unexpected exit {proc.returncode}"

        # Grandchild reaped with the group (retry briefly for teardown).
        for _ in range(50):
            if not _alive(gc_pid):
                break
            time.sleep(0.1)
        assert not _alive(gc_pid), "grandchild orphaned — process group not killed"

        # finally-block ran before exit (temp-dir cleanup / lock release analog).
        assert sentinel.exists(), "caller finally-block did not run on cancel"
    finally:
        if proc.poll() is None:
            proc.kill()
        if "gc_pid" in dir() and gc_pid and _alive(gc_pid):  # pragma: no cover
            os.kill(gc_pid, signal.SIGKILL)


def test_run_cancellable_returns_normally_when_child_exits(tmp_path: Path) -> None:
    from morningbrief.proc import run_cancellable

    result = run_cancellable(
        [sys.executable, "-c", "print('hello'); import sys; sys.exit(0)"],
        timeout_s=30,
    )
    assert result.returncode == 0
    assert "hello" in result.stdout


def test_run_cancellable_times_out_and_kills_group(tmp_path: Path) -> None:
    from morningbrief.proc import run_cancellable

    result = run_cancellable(
        [sys.executable, "-c", "import time; time.sleep(30)"],
        timeout_s=1,
    )
    assert result.returncode == 124
    assert "timeout" in result.stderr
