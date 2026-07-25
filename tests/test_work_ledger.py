from __future__ import annotations

import copy
import json
import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path

import morningbrief.work_ledger as work_ledger_module
import morningbrief.validate as validate_module
from morningbrief.validate import ValidationError
from morningbrief.work_ledger import ConflictError, WorkLedger


def at(day: int, hour: int) -> datetime:
    return datetime(2026, 7, day, hour, tzinfo=timezone.utc)


def make_ledger(tmp_path: Path) -> WorkLedger:
    return WorkLedger(
        db_path=tmp_path / "work.sqlite3",
        briefs_dir=tmp_path / "briefs",
        timezone_name="UTC",
    )


def test_full_lifecycle_publishes_atomic_daily_projection(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    created = ledger.add(
        "评估新支付回调",
        detail="会议行动项",
        actor="human",
        item_id="task-1",
        occurred_at=at(23, 8),
    )
    assert created["item"]["status"] == "pending"

    started = ledger.set_status(
        "task-1",
        "in_progress",
        actor="agent",
        reason="发现待验证链路",
        evidence=["API-142", "Meeting-0723"],
        idempotency_key="start-task-1",
        expected_version=1,
        occurred_at=at(23, 9),
    )
    ledger.add_progress(
        "task-1",
        "样本 12/12 已核对",
        actor="agent",
        reason=None,
        evidence=["probe.json"],
        idempotency_key="note-task-1",
        expected_version=2,
        occurred_at=at(23, 10),
    )
    completed = ledger.set_status(
        "task-1",
        "completed",
        actor="human",
        reason=None,
        evidence=[],
        idempotency_key=None,
        expected_version=3,
        occurred_at=at(23, 11),
    )

    snapshot = ledger.view("2026-07-23")
    item = snapshot["items"][0]
    assert item["status"] == "completed"
    assert item["terminal_date"] == "2026-07-23"
    assert item["version"] == 4
    assert item["events"][1]["reason"] == "发现待验证链路"
    assert item["events"][1]["evidence"] == ["API-142", "Meeting-0723"]
    assert snapshot["latest_agent_event"]["event_id"] != created["event"]["event_id"]
    assert snapshot["recent_history"][0]["items"][0]["id"] == "task-1"
    assert completed["item"]["version"] == 4

    published = json.loads(
        (ledger.briefs_dir / "2026-07-23" / "work.json").read_text(encoding="utf-8")
    )
    assert published["items"][0]["status"] == "completed"
    assert not list((ledger.briefs_dir / "2026-07-23").glob(".work.json.*"))
    assert started["item"]["status"] == "in_progress"


def test_projection_as_of_day_and_active_work_carries_forward(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("跨日任务", item_id="carry", occurred_at=at(21, 8))
    ledger.set_status(
        "carry",
        "in_progress",
        actor="agent",
        reason=None,
        evidence=[],
        idempotency_key=None,
        expected_version=None,
        occurred_at=at(22, 8),
    )
    ledger.set_status(
        "carry",
        "completed",
        actor="human",
        reason=None,
        evidence=[],
        idempotency_key=None,
        expected_version=None,
        occurred_at=at(23, 8),
    )

    day_22 = ledger.view("2026-07-22", publish=False)
    day_23 = ledger.view("2026-07-23", publish=False)
    assert day_22["read_only"] is True
    assert day_22["items"][0]["status"] == "in_progress"
    assert day_23["items"][0]["status"] == "completed"


def test_recent_history_groups_terminal_date_and_includes_cancelled(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("完成项", item_id="done", occurred_at=at(21, 7))
    ledger.set_status(
        "done", "completed", actor="human", reason=None, evidence=[],
        idempotency_key=None, expected_version=None, occurred_at=at(22, 7),
    )
    ledger.add("取消项", item_id="nope", occurred_at=at(22, 8))
    ledger.set_status(
        "nope", "cancelled", actor="agent", reason="不再需要", evidence=[],
        idempotency_key=None, expected_version=None, occurred_at=at(23, 8),
    )

    history = ledger.history("2026-07-23", days=2)
    assert [group["date"] for group in history["recent_history"]] == [
        "2026-07-23",
        "2026-07-22",
    ]
    assert history["recent_history"][0]["items"][0]["status"] == "cancelled"


def test_undo_is_append_only_and_restores_prior_state(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("原始标题", item_id="undo", occurred_at=at(23, 7))
    edited = ledger.edit(
        "undo",
        title="错误标题",
        actor="agent",
        reason="错误推断",
        evidence=["external-1"],
        idempotency_key=None,
        expected_version=1,
        occurred_at=at(23, 8),
    )
    undone = ledger.undo(
        event_id=edited["event"]["event_id"],
        actor="human",
        reason="恢复人工记录",
        expected_version=2,
        occurred_at=at(23, 9),
    )

    assert undone["item"]["title"] == "原始标题"
    assert undone["item"]["version"] == 3
    assert [event["kind"] for event in undone["item"]["events"]] == [
        "created",
        "edited",
        "reverted",
    ]
    with sqlite3.connect(ledger.db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM work_events").fetchone()[0] == 3


def test_idempotency_and_expected_version_prevent_duplicate_or_lost_updates(
    tmp_path: Path,
) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("幂等任务", item_id="idem", occurred_at=at(23, 7))
    first = ledger.add_progress(
        "idem", "同一更新", actor="agent", reason=None, evidence=[],
        idempotency_key="external-event-42", expected_version=1, occurred_at=at(23, 8),
    )
    duplicate = ledger.add_progress(
        "idem", "同一更新", actor="agent", reason=None, evidence=[],
        idempotency_key="external-event-42", expected_version=1, occurred_at=at(23, 8),
    )
    assert duplicate["duplicate"] is True
    assert duplicate["event"]["event_id"] == first["event"]["event_id"]

    try:
        ledger.edit(
            "idem", title="过期写入", actor="human", reason=None, evidence=[],
            idempotency_key=None, expected_version=1, occurred_at=at(23, 9),
        )
    except ConflictError as error:
        assert "version conflict" in str(error)
    else:
        raise AssertionError("stale expected_version should conflict")


def test_concurrent_same_idempotency_key_commits_once(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("并发任务", item_id="concurrent", occurred_at=at(23, 7))
    results: list[dict] = []

    def append() -> None:
        results.append(
            ledger.add_progress(
                "concurrent", "外部回调", actor="agent", reason=None, evidence=["api"],
                idempotency_key="callback-1", expected_version=1, occurred_at=at(23, 8),
            )
        )

    threads = [threading.Thread(target=append), threading.Thread(target=append)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert len(results) == 2
    assert sorted(result["duplicate"] for result in results) == [False, True]
    assert ledger.view("2026-07-23", publish=False)["items"][0]["version"] == 2


def test_work_mutations_do_not_touch_brief_json(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    day_dir = ledger.briefs_dir / "2026-07-23"
    day_dir.mkdir(parents=True)
    brief_path = day_dir / "brief.json"
    original = b'{"date":"2026-07-23","status":"ready"}\n'
    brief_path.write_bytes(original)

    ledger.add("隔离任务", item_id="isolated", occurred_at=at(23, 8))

    assert brief_path.read_bytes() == original
    # Mutations publish today's projection, not the synthetic occurred_at day.
    published = list(ledger.briefs_dir.glob("*/work.json"))
    assert len(published) == 1
    assert published[0].name == "work.json"


def test_replay_uses_commit_sequence_when_timestamps_move_backwards(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("时钟回拨", item_id="clock", occurred_at=at(23, 10))
    ledger.set_status(
        "clock", "in_progress", actor="agent", reason="系统时钟校准",
        evidence=[], idempotency_key=None, expected_version=1, occurred_at=at(23, 9),
    )

    item = ledger.view("2026-07-23", publish=False)["items"][0]
    assert item["status"] == "in_progress"
    assert [event["kind"] for event in item["events"]] == [
        "created",
        "status_changed",
    ]
    assert [event["sequence"] for event in item["events"]] == [1, 2]


def test_history_keeps_earlier_completion_after_reopen(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("多次完成", item_id="repeat", occurred_at=at(21, 7))
    ledger.set_status(
        "repeat", "completed", actor="human", reason=None, evidence=[],
        idempotency_key=None, expected_version=1, occurred_at=at(21, 8),
    )
    ledger.set_status(
        "repeat", "in_progress", actor="agent", reason="发现后续工作", evidence=[],
        idempotency_key=None, expected_version=2, occurred_at=at(22, 8),
    )
    ledger.set_status(
        "repeat", "completed", actor="agent", reason="后续工作完成", evidence=[],
        idempotency_key=None, expected_version=3, occurred_at=at(23, 8),
    )

    groups = ledger.history("2026-07-23", days=3)["recent_history"]
    assert [group["date"] for group in groups] == ["2026-07-23", "2026-07-21"]
    assert [len(group["items"][0]["events"]) for group in groups] == [4, 2]
    assert all(group["items"][0]["status"] == "completed" for group in groups)


def test_idempotent_retry_republishes_after_projection_failure(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    real_atomic_write = work_ledger_module.atomic_write_json
    attempts = 0

    def fail_once(path: Path, payload: dict) -> None:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise OSError("simulated projection failure")
        real_atomic_write(path, payload)

    work_ledger_module.atomic_write_json = fail_once
    try:
        try:
            ledger.add(
                "可恢复发布",
                item_id="recover",
                idempotency_key="recover-once",
            )
        except OSError as error:
            assert "simulated projection failure" in str(error)
        else:
            raise AssertionError("first projection write should fail")

        retry = ledger.add(
            "可恢复发布",
            item_id="recover",
            idempotency_key="recover-once",
        )
    finally:
        work_ledger_module.atomic_write_json = real_atomic_write

    assert retry["duplicate"] is True
    published = list(ledger.briefs_dir.glob("*/work.json"))
    assert len(published) == 1
    assert json.loads(published[0].read_text(encoding="utf-8"))["items"][0]["id"] == "recover"


def test_reusing_idempotency_key_for_different_payload_conflicts(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("原始请求", item_id="same-key", idempotency_key="shared-key")

    try:
        ledger.add("不同请求", item_id="same-key", idempotency_key="shared-key")
    except ConflictError as error:
        assert "idempotency key already used" in str(error)
    else:
        raise AssertionError("different payload must not reuse an idempotency key")


def test_undo_is_idempotent_and_can_revert_creation(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    created = ledger.add("误建任务", item_id="mistake")

    first = ledger.undo(
        event_id=created["event"]["event_id"],
        idempotency_key="undo-create",
        expected_version=1,
    )
    retry = ledger.undo(
        event_id=created["event"]["event_id"],
        idempotency_key="undo-create",
        expected_version=1,
    )

    assert first["item"] is None
    assert retry["duplicate"] is True
    assert retry["event"]["event_id"] == first["event"]["event_id"]
    assert ledger.view(publish=False)["items"] == []


def test_fallback_validator_requires_event_sequence(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("fallback schema", item_id="fallback")
    snapshot = ledger.view(publish=False)
    invalid = copy.deepcopy(snapshot)
    invalid["items"][0]["events"][0].pop("sequence")

    original_jsonschema = validate_module.jsonschema
    validate_module.jsonschema = None
    try:
        validate_module.validate_work_ledger_snapshot(snapshot)
        try:
            validate_module.validate_work_ledger_snapshot(invalid)
        except ValidationError as error:
            assert "sequence" in str(error)
        else:
            raise AssertionError("fallback validator should require event sequence")
    finally:
        validate_module.jsonschema = original_jsonschema


def test_delete_tombstones_hides_from_projection_and_supports_undo(tmp_path: Path) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("误记任务", item_id="gone", occurred_at=at(23, 7))
    deleted = ledger.delete(
        "gone",
        actor="human",
        reason="不需要",
        evidence=[],
        idempotency_key="del-gone",
        expected_version=1,
        occurred_at=at(23, 8),
    )
    assert deleted["event"]["kind"] == "tombstoned"
    assert "tombstoned" not in deleted["item"]  # public mutation payload strips internal flag

    snapshot = ledger.view("2026-07-23", publish=False)
    assert snapshot["schema_version"] == 2
    assert snapshot["items"] == []
    assert snapshot["latest_reversible"]["event"]["event_id"] == deleted["event"]["event_id"]
    assert snapshot["latest_reversible"]["item_id"] == "gone"
    assert snapshot["latest_reversible"]["expected_version"] == 2

    restored = ledger.undo(
        event_id=deleted["event"]["event_id"],
        actor="human",
        reason="误删恢复",
        expected_version=2,
        occurred_at=at(23, 9),
    )
    assert restored["item"]["status"] == "pending"
    assert "tombstoned" not in restored["item"]
    after = ledger.view("2026-07-23", publish=False)
    assert after["items"][0]["id"] == "gone"
    assert after["items"][0]["status"] == "pending"


def test_delete_rejects_terminal_status_and_non_revert_after_tombstone(
    tmp_path: Path,
) -> None:
    ledger = make_ledger(tmp_path)
    ledger.add("完成后再删", item_id="done", occurred_at=at(23, 7))
    ledger.set_status(
        "done",
        "completed",
        actor="human",
        reason=None,
        evidence=[],
        idempotency_key=None,
        expected_version=1,
        occurred_at=at(23, 8),
    )
    try:
        ledger.delete(
            "done",
            actor="human",
            reason=None,
            evidence=[],
            idempotency_key=None,
            expected_version=2,
        )
    except work_ledger_module.LedgerError as error:
        assert "pending or in_progress" in str(error)
    else:
        raise AssertionError("completed items must not be deleteable")

    ledger.add("进行中可删", item_id="active", occurred_at=at(23, 9))
    ledger.delete(
        "active",
        actor="human",
        reason=None,
        evidence=[],
        idempotency_key="del-active",
        expected_version=1,
        occurred_at=at(23, 10),
    )
    duplicate = ledger.delete(
        "active",
        actor="human",
        reason=None,
        evidence=[],
        idempotency_key="del-active",
        expected_version=1,
        occurred_at=at(23, 10),
    )
    assert duplicate["duplicate"] is True
    assert "tombstoned" not in duplicate["item"]
    try:
        ledger.add_progress(
            "active",
            "不应写入",
            actor="human",
            reason=None,
            evidence=[],
            idempotency_key=None,
            expected_version=2,
            occurred_at=at(23, 11),
        )
    except ConflictError as error:
        assert "tombstoned" in str(error)
    else:
        raise AssertionError("non-revert mutation on tombstoned item must conflict")
