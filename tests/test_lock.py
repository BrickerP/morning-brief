import json
import os
import tempfile
from pathlib import Path

from morningbrief.lock import EXIT_LOCKED, acquire, release


def test_dead_lock_recovered():
    with tempfile.TemporaryDirectory() as td:
        lock = Path(td) / "run.lock"
        lock.write_text(
            json.dumps({"pid": 999999, "run_id": "old", "started_at": "2020-01-01T00:00:00Z"}),
            encoding="utf-8",
        )
        acquire(lock, "new", lock_ttl_s=2700)
        data = json.loads(lock.read_text(encoding="utf-8"))
        assert data["run_id"] == "new"
        assert data["pid"] == os.getpid()
        release(lock, "new")
        assert not lock.exists()


def test_live_lock_exits_75():
    with tempfile.TemporaryDirectory() as td:
        lock = Path(td) / "run.lock"
        lock.write_text(
            json.dumps(
                {
                    "pid": os.getpid(),
                    "run_id": "holder",
                    "started_at": "2020-01-01T00:00:00Z",
                }
            ),
            encoding="utf-8",
        )
        try:
            acquire(lock, "other", lock_ttl_s=1)
            raise AssertionError("expected SystemExit")
        except SystemExit as e:
            assert e.code == EXIT_LOCKED
