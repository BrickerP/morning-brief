from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

EXIT_LOCKED = 75


@dataclass
class LockInfo:
    pid: int
    run_id: str
    started_at: str


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def acquire(lock_path: Path, run_id: str, lock_ttl_s: int) -> None:
    """Acquire run lock. Raises SystemExit(75) if a live holder exists."""
    if lock_path.exists():
        try:
            data = json.loads(lock_path.read_text(encoding="utf-8"))
            pid = int(data.get("pid", -1))
            started_at = data.get("started_at", "")
        except (json.JSONDecodeError, ValueError, OSError):
            pid = -1
            started_at = ""

        if _pid_alive(pid):
            # Liveness is the sole gate — never steal a live lock, even past TTL.
            raise SystemExit(EXIT_LOCKED)

        # Dead pid: break. TTL only helps if started_at parse fails / orphaned file.
        if started_at:
            try:
                started = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
                age = (datetime.now(timezone.utc) - started.astimezone(timezone.utc)).total_seconds()
                # Dead + old: clear. Dead + recent: still clear (pid dead wins).
                _ = age, lock_ttl_s
            except ValueError:
                pass
        try:
            lock_path.unlink(missing_ok=True)
        except OSError:
            pass

    payload = {
        "pid": os.getpid(),
        "run_id": run_id,
        "started_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = lock_path.with_suffix(".lock.tmp")
    tmp.write_text(json.dumps(payload), encoding="utf-8")
    os.replace(tmp, lock_path)


def release(lock_path: Path, run_id: str) -> None:
    if not lock_path.exists():
        return
    try:
        data = json.loads(lock_path.read_text(encoding="utf-8"))
        if data.get("run_id") == run_id and int(data.get("pid", -1)) == os.getpid():
            lock_path.unlink(missing_ok=True)
    except (json.JSONDecodeError, ValueError, OSError):
        # Best-effort cleanup of our own lock.
        try:
            if lock_path.exists():
                data = json.loads(lock_path.read_text(encoding="utf-8"))
                if int(data.get("pid", -1)) == os.getpid():
                    lock_path.unlink(missing_ok=True)
        except Exception:
            pass


def sleep_hold_for_tests(seconds: float) -> None:
    time.sleep(seconds)
