from __future__ import annotations

import json
from pathlib import Path

from morningbrief.atomic import atomic_write_json
from morningbrief.config import AppConfig
from morningbrief.session_assistant import (
    apply_session_analysis,
    candidate_anchors,
    find_claude_session,
    normalize_analysis,
)
from morningbrief.work_ledger import WorkLedger


def test_candidate_anchors_strip_terminal_chrome_and_prefer_the_end() -> None:
    anchors = candidate_anchors(
        """
╭────────────────────────────────────────────────────────────╮
│ 早期的普通说明，不应该优先
│ 最终结论：支付回调已经修复，但生产环境的 Pro 支付仍需执行一次完整回归。
╰────────────────────────────────────────────────────────────╯
"""
    )

    assert anchors[0] == "最终结论：支付回调已经修复，但生产环境的 Pro 支付仍需执行一次完整回归。"
    assert all("╭" not in anchor and "╰" not in anchor for anchor in anchors)
    assert candidate_anchors("负数订单是怎么产生的") == ["负数订单是怎么产生的"]


def test_find_claude_session_uses_ending_content_and_includes_subagents(
    tmp_path: Path,
) -> None:
    root = tmp_path / "projects"
    project = root / "-Users-example-work"
    project.mkdir(parents=True)
    wrong = project / "11111111-1111-1111-1111-111111111111.jsonl"
    wrong.write_text('{"message":"另一段会话"}\n', encoding="utf-8")

    session_id = "22222222-2222-2222-2222-222222222222"
    expected = project / f"{session_id}.jsonl"
    expected.write_text(
        '{"message":"最终结论：支付回调已经修复，但生产环境的 Pro 支付仍需执行一次完整回归。"}\n'
        '{"message":"后续只需要回归 Pro 支付和 UI 支付。"}\n',
        encoding="utf-8",
    )
    subagents = project / session_id / "subagents"
    subagents.mkdir(parents=True)
    subagent = subagents / "agent-review.jsonl"
    subagent.write_text('{"message":"子任务验证记录"}\n', encoding="utf-8")

    matched = find_claude_session(
        """
最终结论：支付回调已经修复，但生产环境的 Pro 支付仍需执行一次完整回归。
后续只需要回归 Pro 支付和 UI 支付。
""",
        claude_projects_root=root,
    )

    assert matched["id"] == session_id
    assert matched["source_file"] == str(expected)
    assert matched["confidence"] == "high"
    assert matched["files"] == [str(expected), str(subagent)]


def test_confirmed_analysis_applies_agent_updates_once(tmp_path: Path) -> None:
    ledger = WorkLedger(
        db_path=tmp_path / "work-ledger.sqlite3",
        briefs_dir=tmp_path / "briefs",
    )
    created = ledger.add("生产环境支付回归")
    item = created["item"]
    snapshot = ledger.view(days=14, publish=False)
    analysis_id = "33333333-3333-3333-3333-333333333333"
    session = {
        "id": "44444444-4444-4444-4444-444444444444",
        "project": "-Users-example-work",
        "source_file": "/tmp/44444444-4444-4444-4444-444444444444.jsonl",
        "modified_at": "2026-07-23T08:00:00Z",
        "matched_anchors": ["生产环境的 Pro 支付仍需执行一次完整回归"],
        "confidence": "high",
    }
    payload = {
        "summary": "Claude session 已定位支付问题，仍需执行生产环境回归。",
        "todo_matches": [
            {
                "item_id": item["id"],
                "confidence": 0.96,
                "reason": "会话中的剩余工作与支付回归 Todo 一致。",
            }
        ],
        "proposals": [
            {
                "action": "note",
                "item_id": item["id"],
                "text": "已定位回调问题；剩余 Pro 支付和 UI 支付生产回归。",
                "reason": "Claude session 的最终结论仍保留回归工作。",
            },
            {
                "action": "status",
                "item_id": item["id"],
                "status": "in_progress",
                "reason": "问题已开始处理，但仍有生产回归未完成。",
            },
        ],
    }
    analysis = normalize_analysis(
        payload,
        session=session,
        snapshot=snapshot,
        analysis_id=analysis_id,
    )
    assistant_dir = tmp_path / "assistant"
    atomic_write_json(assistant_dir / f"{analysis_id}.json", analysis)
    cfg = AppConfig()

    applied = apply_session_analysis(
        analysis_id,
        cfg=cfg,
        ledger=ledger,
        assistant_dir=assistant_dir,
    )
    retry = apply_session_analysis(
        analysis_id,
        cfg=cfg,
        ledger=ledger,
        assistant_dir=assistant_dir,
    )
    current = ledger.view(publish=False)["items"][0]

    assert applied["applied_count"] == 2
    assert applied["duplicate"] is False
    assert retry["duplicate"] is True
    assert current["status"] == "in_progress"
    assert current["version"] == 3
    agent_events = [event for event in current["events"] if event["actor"] == "agent"]
    assert len(agent_events) == 2
    assert all(
        event["evidence"] == [f"claude-session:{session['id']}"]
        for event in agent_events
    )
    saved = json.loads(
        (assistant_dir / f"{analysis_id}.json").read_text(encoding="utf-8")
    )
    assert saved["application"]["status"] == "applied"
    assert saved["applied_at"]


def test_normalize_analysis_drops_noop_and_duplicate_proposals(tmp_path: Path) -> None:
    ledger = WorkLedger(
        db_path=tmp_path / "work-ledger.sqlite3",
        briefs_dir=tmp_path / "briefs",
    )
    created = ledger.add("已在处理的任务")
    started = ledger.set_status(
        created["item"]["id"],
        "in_progress",
        actor="human",
        reason=None,
        evidence=[],
        idempotency_key=None,
        expected_version=1,
        occurred_at=None,
    )
    noted = ledger.add_progress(
        created["item"]["id"],
        "已经记录的进展",
        actor="human",
        reason=None,
        evidence=[],
        idempotency_key=None,
        expected_version=2,
        occurred_at=None,
    )
    snapshot = ledger.view(publish=False)
    session = {
        "id": "55555555-5555-5555-5555-555555555555",
        "project": "-Users-example-work",
        "source_file": "/tmp/session.jsonl",
        "modified_at": "2026-07-23T08:00:00Z",
        "matched_anchors": ["已经记录的进展"],
        "confidence": "high",
    }
    payload = {
        "summary": "没有新增变化。",
        "todo_matches": [],
        "proposals": [
            {
                "action": "status",
                "item_id": noted["item"]["id"],
                "status": "in_progress",
            },
            {
                "action": "note",
                "item_id": noted["item"]["id"],
                "text": "已经记录的进展",
            },
            {
                "action": "edit",
                "item_id": noted["item"]["id"],
                "title": "已在处理的任务",
                "detail": "",
            },
        ],
    }

    analysis = normalize_analysis(
        payload,
        session=session,
        snapshot=snapshot,
        analysis_id="66666666-6666-6666-6666-666666666666",
    )

    assert started["item"]["status"] == "in_progress"
    assert analysis["proposals"] == []
