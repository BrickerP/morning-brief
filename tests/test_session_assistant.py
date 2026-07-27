from __future__ import annotations

import json
import os
from pathlib import Path

from morningbrief.atomic import atomic_write_json
from morningbrief.config import AppConfig
from morningbrief.proc import ProcResult
from morningbrief.session_assistant import (
    SUMMARY_RECIPE_VERSION,
    SessionAssistantError,
    _extract_tail_turns,
    _session_preview,
    _validate_session_path,
    analyze_confirmed_session,
    apply_session_analysis,
    candidate_anchors,
    ensure_session_summaries,
    find_claude_session,
    list_recent_sessions,
    normalize_analysis,
    summarize_session,
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
    recap = candidate_anchors(
        "✻ Sautéed for 2m 36s\n※ recap: 已经完成团队空间入口定位。"
    )
    assert recap == ["已经完成团队空间入口定位。"]


def test_find_claude_session_ignores_terminal_timing_and_normalizes_recap(
    tmp_path: Path,
) -> None:
    root = tmp_path / "projects"
    project = root / "-Users-example-work"
    project.mkdir(parents=True)
    session_id = "26d1d2db-ec1d-425c-9f52-09d25d844cab"
    expected = project / f"{session_id}.jsonl"
    recap = (
        "Stripe 订阅卡死排查已收尾:三篇 KU 文档更新到 243 户、SQL 做成可复制代码块,"
        "705 已解卡。刚定位 user-d14vbnwda77k 不是 bug,是没建团队空间,"
        "给了他 medo.dev/space/manage。下一步:如需要,用 chrome-use 登该账号实测此页是否正常。"
    )
    expected.write_text(
        json.dumps({"type": "system", "content": recap}, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    matched = find_claude_session(
        f"""
要不要我用 chrome-use 登进去实测一下这个页面对他账号是否正常?

✻ Sautéed for 2m 36s

※ recap: {recap}
""",
        claude_projects_root=root,
    )

    assert matched["id"] == session_id
    assert matched["matched_anchors"] == [recap]


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


def _write_session(root: Path, project: str, session_id: str, lines: list[dict]) -> Path:
    project_dir = root / project
    project_dir.mkdir(parents=True, exist_ok=True)
    path = project_dir / f"{session_id}.jsonl"
    path.write_text(
        "\n".join(json.dumps(line, ensure_ascii=False) for line in lines) + "\n",
        encoding="utf-8",
    )
    return path


def test_validate_session_path_accepts_parent_and_rejects_others(tmp_path: Path) -> None:
    root = tmp_path / "projects"
    session_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    good = _write_session(root, "-Users-example-work", session_id, [{"type": "user"}])
    subagents = root / "-Users-example-work" / session_id / "subagents"
    subagents.mkdir(parents=True)
    sub = subagents / "agent-review.jsonl"
    sub.write_text("{}\n", encoding="utf-8")

    assert _validate_session_path(good, root) == good.resolve()

    # Subagent transcript is four parts under root — rejected.
    try:
        _validate_session_path(sub, root)
    except SessionAssistantError:
        pass
    else:  # pragma: no cover
        raise AssertionError("subagent path should be rejected")

    # Outside the projects root — rejected.
    outsider = tmp_path / "elsewhere.jsonl"
    outsider.write_text("{}\n", encoding="utf-8")
    try:
        _validate_session_path(outsider, root)
    except SessionAssistantError:
        pass
    else:  # pragma: no cover
        raise AssertionError("outside-root path should be rejected")

    # Non-.jsonl — rejected.
    txt = root / "-Users-example-work" / "note.txt"
    txt.write_text("hi", encoding="utf-8")
    try:
        _validate_session_path(txt, root)
    except SessionAssistantError:
        pass
    else:  # pragma: no cover
        raise AssertionError("non-jsonl path should be rejected")


def test_list_recent_sessions_orders_and_filters(tmp_path: Path) -> None:
    root = tmp_path / "projects"
    older = _write_session(
        root, "-proj-a", "11111111-1111-1111-1111-111111111111",
        [{"type": "summary", "summary": "旧会话摘要"}],
    )
    newer = _write_session(
        root, "-proj-b", "22222222-2222-2222-2222-222222222222",
        [{"type": "user", "message": {"content": "帮我排查支付回调"}}],
    )
    os.utime(older, (1000, 1000))
    os.utime(newer, (2000, 2000))
    # A subagent transcript must never surface as a top-level session.
    subagents = root / "-proj-b" / "22222222-2222-2222-2222-222222222222" / "subagents"
    subagents.mkdir(parents=True)
    (subagents / "agent.jsonl").write_text("{}\n", encoding="utf-8")

    listing = list_recent_sessions(claude_projects_root=root)
    ids = [s["id"] for s in listing["sessions"]]
    assert ids == [
        "claude:22222222-2222-2222-2222-222222222222",
        "claude:11111111-1111-1111-1111-111111111111",
    ]
    assert listing["sessions"][0]["source"] == "claude"
    assert listing["sessions"][0]["preview"] == "帮我排查支付回调"
    # Fallback preview prefers latest user text; summary-type records are not used.
    assert listing["sessions"][1]["preview"] == ""
    assert listing["sessions"][0]["summary"] is None
    assert listing["sessions"][0]["summary_status"] == "pending"

    only_a = list_recent_sessions(project="-proj-a", claude_projects_root=root)
    assert [s["id"] for s in only_a["sessions"]] == [
        "claude:11111111-1111-1111-1111-111111111111"
    ]


def test_summarize_session_persists_once_per_fingerprint(tmp_path: Path) -> None:
    root = tmp_path / "projects"
    session_id = "66666666-6666-6666-6666-666666666666"
    session_file = _write_session(
        root,
        "-proj",
        session_id,
        [{"type": "user", "message": {"content": "修支付回调并回归"}}],
    )
    summaries = tmp_path / "summaries"
    workspaces = tmp_path / "ws"
    calls = {"n": 0}

    def fake_agent(args, *, timeout_s, env=None):
        calls["n"] += 1
        return ProcResult(
            0,
            json.dumps({"summary": f"第{calls['n']}次摘要：支付回调已修。"}, ensure_ascii=False),
            "",
        )

    cfg = AppConfig(synth_timeout_s=30)
    first = summarize_session(
        session_file,
        cfg=cfg,
        claude_projects_root=root,
        summaries_dir=summaries,
        agent_workspace_dir=workspaces,
        agent_runner=fake_agent,
    )
    assert first["cached"] is False
    assert first["recipe_version"] == SUMMARY_RECIPE_VERSION
    assert first["summary"] == "第1次摘要：支付回调已修。"
    cache_name = f"claude_{session_id}.json"
    cached_doc = json.loads((summaries / cache_name).read_text(encoding="utf-8"))
    assert cached_doc["recipe_version"] == SUMMARY_RECIPE_VERSION

    # Old whole-session caches without recipe_version must not hit.
    cached_doc.pop("recipe_version")
    (summaries / cache_name).write_text(
        json.dumps(cached_doc, ensure_ascii=False),
        encoding="utf-8",
    )
    refreshed = summarize_session(
        session_file,
        cfg=cfg,
        claude_projects_root=root,
        summaries_dir=summaries,
        agent_workspace_dir=workspaces,
        agent_runner=fake_agent,
    )
    assert refreshed["cached"] is False
    assert calls["n"] == 2

    second = summarize_session(
        session_file,
        cfg=cfg,
        claude_projects_root=root,
        summaries_dir=summaries,
        agent_workspace_dir=workspaces,
        agent_runner=fake_agent,
    )
    assert second["cached"] is True
    assert second["summary"] == "第2次摘要：支付回调已修。"
    assert calls["n"] == 2

    ensured = ensure_session_summaries(
        limit=5,
        cfg=cfg,
        claude_projects_root=root,
        summaries_dir=summaries,
        agent_workspace_dir=workspaces,
        agent_runner=fake_agent,
    )
    assert ensured["summarized"] == 0
    assert ensured["skipped"] == 1
    assert ensured["sessions"][0]["summary_status"] == "ready"
    assert calls["n"] == 2

    # Tool/assistant noise that does not change the dialogue tail must NOT re-run.
    with session_file.open("a", encoding="utf-8") as handle:
        handle.write(
            json.dumps(
                {"type": "assistant", "message": {"content": "内部工具噪声，不进新 user turn"}},
                ensure_ascii=False,
            )
            + "\n"
        )
    noise = summarize_session(
        session_file,
        cfg=cfg,
        claude_projects_root=root,
        summaries_dir=summaries,
        agent_workspace_dir=workspaces,
        agent_runner=fake_agent,
    )
    assert noise["cached"] is True
    assert calls["n"] == 2

    # A new user turn changes the exact fingerprint, but list/ensure keep the
    # stale blurb (no auto re-agent). Explicit summarize_session still refreshes.
    with session_file.open("a", encoding="utf-8") as handle:
        handle.write(
            json.dumps(
                {"type": "user", "message": {"content": "追加：生产回归通过"}},
                ensure_ascii=False,
            )
            + "\n"
        )
    ensured_stale = ensure_session_summaries(
        limit=5,
        cfg=cfg,
        claude_projects_root=root,
        summaries_dir=summaries,
        agent_workspace_dir=workspaces,
        agent_runner=fake_agent,
    )
    assert ensured_stale["summarized"] == 0
    assert ensured_stale["sessions"][0]["summary_status"] == "ready"
    assert calls["n"] == 2

    third = summarize_session(
        session_file,
        cfg=cfg,
        claude_projects_root=root,
        summaries_dir=summaries,
        agent_workspace_dir=workspaces,
        agent_runner=fake_agent,
    )
    assert third["cached"] is False
    assert third["summary"] == "第3次摘要：支付回调已修。"
    assert calls["n"] == 3


def test_session_preview_prefers_latest_user_not_opener(tmp_path: Path) -> None:
    root = tmp_path / "projects"
    path = _write_session(
        root, "-proj", "33333333-3333-3333-3333-333333333333",
        [
            {"type": "user", "message": {"content": [{"text": "第一条用户消息"}]}},
            {"type": "assistant", "message": {"content": "回答"}},
            {"type": "user", "message": {"content": "最后在做生产回归"}},
            {"type": "assistant", "message": {"content": "好的"}},
        ],
    )
    assert _session_preview(path) == "最后在做生产回归"


def test_session_preview_skips_task_notification_noise(tmp_path: Path) -> None:
    root = tmp_path / "projects"
    path = _write_session(
        root, "-proj", "88888888-8888-8888-8888-888888888888",
        [
            {"type": "user", "message": {"content": "对齐 Stripe promo jar"}},
            {"type": "assistant", "message": {"content": "ok"}},
            {
                "type": "user",
                "message": {
                    "content": (
                        '<task-notification> <task-id>x</task-id> '
                        '<summary>Monitor event: "BE started"</summary>'
                    )
                },
            },
        ],
    )
    assert _session_preview(path) == "对齐 Stripe promo jar"


def test_extract_tail_turns_keeps_last_user_started_window(tmp_path: Path) -> None:
    root = tmp_path / "projects"
    lines = []
    for index in range(1, 6):
        lines.append({"type": "user", "message": {"content": f"用户{index}"}})
        lines.append({"type": "assistant", "message": {"content": f"助手{index}"}})
    path = _write_session(root, "-proj", "77777777-7777-7777-7777-777777777777", lines)
    tail = _extract_tail_turns(path, max_turns=2)
    assert [message["text"] for message in tail] == ["用户4", "助手4", "用户5", "助手5"]


def test_analyze_confirmed_session_runs_without_locate(tmp_path: Path) -> None:
    root = tmp_path / "projects"
    session_id = "44444444-4444-4444-4444-444444444444"
    session_file = _write_session(
        root, "-Users-example-work", session_id,
        [{"type": "user", "message": {"content": "生产环境支付回归"}}],
    )
    ledger = WorkLedger(
        db_path=tmp_path / "work-ledger.sqlite3",
        briefs_dir=tmp_path / "briefs",
    )
    created = ledger.add("生产环境支付回归")
    item_id = created["item"]["id"]

    payload = {
        "summary": "会话已定位支付问题，仍需生产回归。",
        "todo_matches": [
            {"item_id": item_id, "confidence": 0.9, "reason": "剩余工作一致"}
        ],
        "proposals": [
            {
                "action": "note",
                "item_id": item_id,
                "text": "已定位回调问题；剩余生产回归。",
                "reason": "会话最终结论。",
            }
        ],
    }

    def fake_agent(args, *, timeout_s, env=None):  # noqa: ANN001, ARG001
        return ProcResult(0, json.dumps(payload, ensure_ascii=False), "")

    analysis = analyze_confirmed_session(
        session_file,
        cfg=AppConfig(),
        ledger=ledger,
        claude_projects_root=root,
        assistant_dir=tmp_path / "assistant",
        agent_workspace_dir=tmp_path / "ws",
        agent_runner=fake_agent,
    )

    assert analysis["session"]["id"] == session_id
    assert analysis["summary"] == "会话已定位支付问题，仍需生产回归。"
    assert len(analysis["proposals"]) == 1
    assert analysis["proposals"][0]["action"] == "note"
