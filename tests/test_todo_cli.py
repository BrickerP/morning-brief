from __future__ import annotations

import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path
from typing import Any


PACKAGE_ROOT = Path(__file__).resolve().parents[1] / "packages" / "morningbrief"

CLI_DRIVER = r"""
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["MORNINGBRIEF_TEST_ROOT"])
import morningbrief.paths as paths
paths.APP_SUPPORT = root
paths.BRIEFS_DIR = root / "briefs"
paths.LOGS_DIR = root / "logs"
paths.AGENT_WS_DIR = root / "agent-workspaces"
paths.WORK_LEDGER_DB = root / "work-ledger.sqlite3"
paths.CONFIG_DIR = root / "config"
paths.CONFIG_PATH = paths.CONFIG_DIR / "config.toml"

import morningbrief.config as config
config.CONFIG_PATH = paths.CONFIG_PATH
import morningbrief.work_ledger as work_ledger

if os.environ.get("MORNINGBRIEF_TEST_NOW"):
    fixed_now = work_ledger._parse_timestamp(os.environ["MORNINGBRIEF_TEST_NOW"])
    work_ledger._utc_now = lambda: fixed_now

original_ledger = work_ledger.WorkLedger

class IsolatedWorkLedger(original_ledger):
    def __init__(self, *args, **kwargs):
        kwargs.setdefault("db_path", paths.WORK_LEDGER_DB)
        kwargs.setdefault("briefs_dir", paths.BRIEFS_DIR)
        super().__init__(*args, **kwargs)

work_ledger.WorkLedger = IsolatedWorkLedger
import morningbrief.cli as cli
if hasattr(cli, "WorkLedger"):
    cli.WorkLedger = IsolatedWorkLedger
cli.main(json.loads(sys.argv[1]))
"""


def _run_cli(
    root: Path,
    *args: str,
    now: str | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["MORNINGBRIEF_TEST_ROOT"] = str(root)
    env["PYTHONPATH"] = str(PACKAGE_ROOT)
    if now:
        env["MORNINGBRIEF_TEST_NOW"] = now
    else:
        env.pop("MORNINGBRIEF_TEST_NOW", None)
    return subprocess.run(
        [sys.executable, "-c", CLI_DRIVER, json.dumps(["todo", *args])],
        cwd=PACKAGE_ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )


def _json_result(
    root: Path,
    *args: str,
    now: str | None = None,
) -> dict[str, Any]:
    result = _run_cli(root, *args, now=now)
    assert result.returncode == 0, (
        f"briefctl todo {' '.join(args)} failed\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    parsed = json.loads(result.stdout)
    assert isinstance(parsed, dict)
    return parsed


def _add(root: Path, title: str = "评估新支付回调") -> dict[str, Any]:
    return _json_result(root, "add", title)


def test_lifecycle_complete_history_and_undo_preserves_progress(tmp_path: Path) -> None:
    created = _add(tmp_path)
    item_id = created["item"]["id"]

    started = _json_result(
        tmp_path,
        "status",
        item_id,
        "in_progress",
        "--expected-version",
        str(created["item"]["version"]),
    )
    note = _json_result(
        tmp_path,
        "note",
        item_id,
        "API 样本 12/12 已核对，无新异常",
        "--expected-version",
        str(started["item"]["version"]),
    )
    completed = _json_result(
        tmp_path,
        "status",
        item_id,
        "completed",
        "--expected-version",
        str(note["item"]["version"]),
    )

    history = _json_result(tmp_path, "history")
    history_items = [
        item
        for group in history["recent_history"]
        for item in group["items"]
    ]
    archived = next(item for item in history_items if item["id"] == item_id)
    assert archived["status"] == "completed"

    undone = _json_result(
        tmp_path,
        "undo",
        completed["event"]["event_id"],
        "--expected-version",
        str(completed["item"]["version"]),
    )
    assert undone["event"]["kind"] == "reverted"
    assert undone["event"]["target_event_id"] == completed["event"]["event_id"]
    assert undone["item"]["status"] == "in_progress"
    assert any(
        event["event_id"] == note["event"]["event_id"]
        for event in undone["item"]["events"]
    )


def test_agent_event_preserves_actor_reason_and_evidence(tmp_path: Path) -> None:
    created = _add(tmp_path)

    started = _json_result(
        tmp_path,
        "status",
        created["item"]["id"],
        "in_progress",
        "--actor",
        "agent",
        "--reason",
        "会议后检测到待验证的回调链路",
        "--evidence",
        "API-142",
        "--evidence",
        "Meeting-0723",
    )

    event = started["event"]
    assert event["actor"] == "agent"
    assert event["reason"] == "会议后检测到待验证的回调链路"
    assert event["evidence"] == ["API-142", "Meeting-0723"]


def test_view_returns_schema_shaped_json_and_publishes_work_file(tmp_path: Path) -> None:
    _add(tmp_path, "保留 JSON 合约")

    view = _json_result(tmp_path, "view")

    assert view["schema_version"] == 1
    assert set(view) == {
        "schema_version",
        "date",
        "generated_at",
        "read_only",
        "items",
        "recent_history",
        "latest_agent_event",
    }
    assert view["items"][0]["status"] == "pending"
    published = tmp_path / "briefs" / view["date"] / "work.json"
    assert published.is_file()
    assert json.loads(published.read_text(encoding="utf-8")) == view


def test_idempotency_retry_returns_original_event_without_duplicate(tmp_path: Path) -> None:
    args = (
        "add",
        "幂等创建",
        "--actor",
        "agent",
        "--idempotency-key",
        "external-request-142",
    )

    first = _json_result(tmp_path, *args)
    retry = _json_result(tmp_path, *args)
    view = _json_result(tmp_path, "view")

    assert first["duplicate"] is False
    assert retry["duplicate"] is True
    assert retry["event"]["event_id"] == first["event"]["event_id"]
    assert retry["item"]["id"] == first["item"]["id"]
    assert [item["title"] for item in view["items"]] == ["幂等创建"]


def test_expected_version_conflict_does_not_mutate_item(tmp_path: Path) -> None:
    created = _add(tmp_path, "并发保护")
    item_id = created["item"]["id"]
    _json_result(
        tmp_path,
        "status",
        item_id,
        "in_progress",
        "--expected-version",
        str(created["item"]["version"]),
    )

    conflict = _run_cli(
        tmp_path,
        "note",
        item_id,
        "基于过期版本的更新",
        "--expected-version",
        str(created["item"]["version"]),
    )
    view = _json_result(tmp_path, "view")
    item = next(entry for entry in view["items"] if entry["id"] == item_id)

    assert conflict.returncode != 0
    assert "version conflict" in (conflict.stdout + conflict.stderr).lower()
    assert item["version"] == 2
    assert all(
        event.get("payload", {}).get("text") != "基于过期版本的更新"
        for event in item["events"]
    )


def test_completion_is_projected_by_completion_date_and_recent_range(
    tmp_path: Path,
) -> None:
    today = date.today()
    old_day = today - timedelta(days=8)
    recent_day = today - timedelta(days=2)
    created = _json_result(
        tmp_path,
        "add",
        "跨日完成项",
        now=f"{old_day.isoformat()}T01:00:00Z",
    )
    item_id = created["item"]["id"]
    _json_result(
        tmp_path,
        "status",
        item_id,
        "completed",
        now=f"{recent_day.isoformat()}T08:00:00Z",
    )

    recent = _json_result(tmp_path, "history", "--date", today.isoformat(), "--days", "7")
    completion_group = next(
        group for group in recent["recent_history"] if group["date"] == recent_day.isoformat()
    )
    assert [item["id"] for item in completion_group["items"]] == [item_id]

    historical = _json_result(tmp_path, "view", "--date", old_day.isoformat())
    old_item = next(item for item in historical["items"] if item["id"] == item_id)
    assert old_item["status"] == "pending"
    assert old_item["terminal_date"] is None
    assert historical["read_only"] is True


def test_empty_ledger_returns_valid_empty_projection(tmp_path: Path) -> None:
    view = _json_result(tmp_path, "view")
    history = _json_result(tmp_path, "history")

    assert view["items"] == []
    assert view["recent_history"] == []
    assert view["latest_agent_event"] is None
    assert history["recent_history"] == []


def test_corrupted_database_fails_without_overwriting_it(tmp_path: Path) -> None:
    database = tmp_path / "work-ledger.sqlite3"
    corrupted = b"not a sqlite database"
    tmp_path.mkdir(parents=True, exist_ok=True)
    database.write_bytes(corrupted)

    result = _run_cli(tmp_path, "view")

    assert result.returncode != 0
    assert database.read_bytes() == corrupted
    assert not list((tmp_path / "briefs").glob("*/work.json"))


def test_concurrent_unique_adds_do_not_lose_items(tmp_path: Path) -> None:
    titles = [f"并发任务 {index}" for index in range(12)]

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda title: _run_cli(tmp_path, "add", title), titles))

    failures = [
        f"{result.returncode}: {result.stdout} {result.stderr}"
        for result in results
        if result.returncode != 0
    ]
    assert failures == []
    view = _json_result(tmp_path, "view")
    assert {item["title"] for item in view["items"]} == set(titles)
    assert len({item["id"] for item in view["items"]}) == len(titles)


def test_concurrent_notes_append_all_events_without_lost_updates(tmp_path: Path) -> None:
    created = _add(tmp_path, "收集并发进展")
    item_id = created["item"]["id"]
    notes = [f"进展 {index}" for index in range(12)]

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(
            pool.map(lambda text: _run_cli(tmp_path, "note", item_id, text), notes)
        )

    failures = [
        f"{result.returncode}: {result.stdout} {result.stderr}"
        for result in results
        if result.returncode != 0
    ]
    assert failures == []
    view = _json_result(tmp_path, "view")
    item = next(entry for entry in view["items"] if entry["id"] == item_id)
    progress = [
        event["payload"]["text"]
        for event in item["events"]
        if event["kind"] == "progress_added"
    ]
    assert set(progress) == set(notes)
    assert len(progress) == len(notes)
    assert item["version"] == 1 + len(notes)
