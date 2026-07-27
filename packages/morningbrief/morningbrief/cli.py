from __future__ import annotations

import argparse
import json
import sqlite3
import subprocess
import sys
from pathlib import Path

from morningbrief.config import load_config
from morningbrief.doctor import run_doctor
from morningbrief.lock import EXIT_LOCKED
from morningbrief.paths import brief_dir, ensure_app_dirs
from morningbrief.pipeline import run_pipeline, synth_brief
from morningbrief.schedule import install_schedule, kickstart, uninstall_schedule
from morningbrief.session_assistant import (
    SessionAssistantError,
    analyze_claude_session,
    analyze_confirmed_session,
    apply_session_analysis,
    ensure_session_summaries,
    find_claude_session,
    list_recent_sessions,
    summarize_session,
)
from morningbrief.timeutil import date_str, local_today
from morningbrief.work_ledger import LedgerError, WorkLedger


def _add_mutation_arguments(parser: argparse.ArgumentParser, *, expected_version: bool = True) -> None:
    parser.add_argument("--actor", choices=("human", "agent", "system"), default="human")
    parser.add_argument("--reason")
    parser.add_argument("--evidence", action="append", default=[])
    parser.add_argument("--idempotency-key")
    if expected_version:
        parser.add_argument("--expected-version", type=int)


def _print_json(data: object) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="briefctl", description="Morning Brief controller")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_run = sub.add_parser("run", help="Fetch sources and synthesize brief")
    p_run.add_argument("--date", help="YYYY-MM-DD (default: local today)")
    p_run.add_argument("--skip-synth", action="store_true", help="Fetch-only / degraded without agent")

    p_synth = sub.add_parser("synth", help="Synthesize brief from already-fetched sources")
    p_synth.add_argument("--date", help="YYYY-MM-DD (default: local today)")

    sub.add_parser("doctor", help="Validate environment")
    sub.add_parser("status", help="Show today's run.json")
    sub.add_parser("sections", help="List sections from today's brief.json")
    sub.add_parser("open", help="Open today's brief folder in Finder")
    sub.add_parser("install-schedule", help="Install launchd 07:30 job")
    sub.add_parser("uninstall-schedule", help="Remove launchd job")
    sub.add_parser("kickstart", help="Force-start launchd job now")

    p_todo = sub.add_parser("todo", help="View and update the work ledger")
    todo_sub = p_todo.add_subparsers(dest="todo_cmd", required=True)

    p_todo_view = todo_sub.add_parser("view", help="Publish and return a daily projection")
    p_todo_view.add_argument("--date", help="YYYY-MM-DD (default: local today)")
    p_todo_view.add_argument("--days", type=int, default=7)

    p_todo_add = todo_sub.add_parser("add", help="Capture a pending work item")
    p_todo_add.add_argument("title")
    p_todo_add.add_argument("--detail", default="")
    p_todo_add.add_argument("--item-id")
    _add_mutation_arguments(p_todo_add, expected_version=False)

    p_todo_edit = todo_sub.add_parser("edit", help="Edit a work item's title or detail")
    p_todo_edit.add_argument("item_id")
    p_todo_edit.add_argument("--title")
    p_todo_edit.add_argument("--detail")
    _add_mutation_arguments(p_todo_edit)

    p_todo_status = todo_sub.add_parser("status", help="Set a work item's status")
    p_todo_status.add_argument("item_id")
    p_todo_status.add_argument(
        "status", choices=("pending", "in_progress", "completed")
    )
    _add_mutation_arguments(p_todo_status)

    p_todo_note = todo_sub.add_parser("note", help="Append progress, a blocker, or a next step")
    p_todo_note.add_argument("item_id")
    p_todo_note.add_argument("text")
    _add_mutation_arguments(p_todo_note)

    p_todo_note_edit = todo_sub.add_parser(
        "note-edit",
        help="Edit the text of an existing progress_added event (append-only overlay)",
    )
    p_todo_note_edit.add_argument("item_id")
    p_todo_note_edit.add_argument("event_id")
    p_todo_note_edit.add_argument("text")
    _add_mutation_arguments(p_todo_note_edit)

    p_todo_delete = todo_sub.add_parser(
        "delete",
        help="Hide a pending/in_progress item from projections (append-only tombstone)",
    )
    p_todo_delete.add_argument("item_id")
    _add_mutation_arguments(p_todo_delete)

    p_todo_undo = todo_sub.add_parser("undo", help="Revert one mutation event")
    p_todo_undo.add_argument("event_id")
    p_todo_undo.add_argument("--actor", choices=("human", "agent", "system"), default="human")
    p_todo_undo.add_argument("--reason")
    p_todo_undo.add_argument("--idempotency-key")
    p_todo_undo.add_argument("--expected-version", type=int)

    p_todo_history = todo_sub.add_parser("history", help="Return recent terminal work")
    p_todo_history.add_argument("--date", help="YYYY-MM-DD (default: local today)")
    p_todo_history.add_argument("--days", type=int, default=7)

    p_assistant = sub.add_parser(
        "assistant",
        help="Analyze a Claude session and propose confirmed Todo updates",
    )
    assistant_sub = p_assistant.add_subparsers(dest="assistant_cmd", required=True)
    p_assistant_analyze = assistant_sub.add_parser(
        "analyze",
        help="Find and fully review a Claude session from pasted ending text",
    )
    p_assistant_analyze.add_argument(
        "--input",
        default="-",
        help="UTF-8 file containing the pasted ending, or - for stdin",
    )
    p_assistant_analyze.add_argument(
        "--session-file",
        help="Analyze this exact parent session JSONL, skipping the locate phase",
    )
    p_assistant_locate = assistant_sub.add_parser(
        "locate",
        help="Locate the Claude session for pasted ending text without analyzing",
    )
    p_assistant_locate.add_argument(
        "--input",
        default="-",
        help="UTF-8 file containing the pasted ending, or - for stdin",
    )
    p_assistant_sessions = assistant_sub.add_parser(
        "sessions",
        help="List recent Claude (10) / Codex (5) / Cursor (5) sessions",
    )
    p_assistant_sessions.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Override Claude session count (default 10); Codex/Cursor stay at 5",
    )
    p_assistant_sessions.add_argument("--project", help="Restrict to one Claude project directory name")
    p_assistant_summarize = assistant_sub.add_parser(
        "summarize",
        help="Persist agent summaries for recent sessions (skips fingerprint cache hits)",
    )
    p_assistant_summarize.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Override Claude session count when summarizing the recent list",
    )
    p_assistant_summarize.add_argument("--project", help="Restrict to one project directory name")
    p_assistant_summarize.add_argument(
        "--session-file",
        help="Summarize this exact parent session JSONL instead of the recent list",
    )
    p_assistant_summarize.add_argument(
        "--force",
        action="store_true",
        help="Ignore the fingerprint cache and re-run the agent",
    )
    p_assistant_apply = assistant_sub.add_parser(
        "apply",
        help="Apply the proposals from a prior analysis after confirmation",
    )
    p_assistant_apply.add_argument("analysis_id")

    args = parser.parse_args(argv)
    ensure_app_dirs()
    cfg = load_config()

    if args.cmd == "assistant":
        try:
            if args.assistant_cmd == "analyze":
                if args.session_file:
                    result = analyze_confirmed_session(args.session_file, cfg=cfg)
                else:
                    if args.input == "-":
                        tail = sys.stdin.read()
                    else:
                        tail = Path(args.input).read_text(encoding="utf-8")
                    result = analyze_claude_session(tail, cfg=cfg)
            elif args.assistant_cmd == "locate":
                if args.input == "-":
                    tail = sys.stdin.read()
                else:
                    tail = Path(args.input).read_text(encoding="utf-8")
                result = find_claude_session(tail)
            elif args.assistant_cmd == "sessions":
                result = list_recent_sessions(limit=args.limit, project=args.project)
            elif args.assistant_cmd == "summarize":
                if args.session_file:
                    result = summarize_session(
                        args.session_file,
                        cfg=cfg,
                        force=args.force,
                    )
                else:
                    result = ensure_session_summaries(
                        limit=args.limit,
                        project=args.project,
                        cfg=cfg,
                    )
            else:
                result = apply_session_analysis(args.analysis_id, cfg=cfg)
        except (SessionAssistantError, LedgerError, OSError, sqlite3.Error, ValueError) as error:
            _print_json({"error": {"type": error.__class__.__name__, "message": str(error)}})
            raise SystemExit(2)
        _print_json(result)
        raise SystemExit(0)

    if args.cmd == "todo":
        try:
            ledger = WorkLedger(timezone_name=cfg.timezone)
            if args.todo_cmd == "view":
                result = ledger.view(args.date, days=args.days)
            elif args.todo_cmd == "add":
                result = ledger.add(
                    args.title,
                    detail=args.detail,
                    actor=args.actor,
                    reason=args.reason,
                    evidence=args.evidence,
                    item_id=args.item_id,
                    idempotency_key=args.idempotency_key,
                )
            elif args.todo_cmd == "edit":
                result = ledger.edit(
                    args.item_id,
                    title=args.title,
                    detail=args.detail,
                    actor=args.actor,
                    reason=args.reason,
                    evidence=args.evidence,
                    idempotency_key=args.idempotency_key,
                    expected_version=args.expected_version,
                )
            elif args.todo_cmd == "status":
                result = ledger.set_status(
                    args.item_id,
                    args.status,
                    actor=args.actor,
                    reason=args.reason,
                    evidence=args.evidence,
                    idempotency_key=args.idempotency_key,
                    expected_version=args.expected_version,
                    occurred_at=None,
                )
            elif args.todo_cmd == "note":
                result = ledger.add_progress(
                    args.item_id,
                    args.text,
                    actor=args.actor,
                    reason=args.reason,
                    evidence=args.evidence,
                    idempotency_key=args.idempotency_key,
                    expected_version=args.expected_version,
                    occurred_at=None,
                )
            elif args.todo_cmd == "note-edit":
                result = ledger.edit_progress(
                    args.item_id,
                    args.event_id,
                    args.text,
                    actor=args.actor,
                    reason=args.reason,
                    evidence=args.evidence,
                    idempotency_key=args.idempotency_key,
                    expected_version=args.expected_version,
                    occurred_at=None,
                )
            elif args.todo_cmd == "delete":
                result = ledger.delete(
                    args.item_id,
                    actor=args.actor,
                    reason=args.reason,
                    evidence=args.evidence,
                    idempotency_key=args.idempotency_key,
                    expected_version=args.expected_version,
                    occurred_at=None,
                )
            elif args.todo_cmd == "undo":
                result = ledger.undo(
                    event_id=args.event_id,
                    actor=args.actor,
                    reason=args.reason,
                    idempotency_key=args.idempotency_key,
                    expected_version=args.expected_version,
                )
            else:
                result = ledger.history(args.date, days=args.days)
        except (LedgerError, OSError, sqlite3.Error, ValueError) as error:
            _print_json({"error": {"type": error.__class__.__name__, "message": str(error)}})
            raise SystemExit(2)
        _print_json(result)
        raise SystemExit(0)

    if args.cmd == "doctor":
        raise SystemExit(run_doctor())

    if args.cmd == "run":
        try:
            state = run_pipeline(date=args.date, skip_synth=args.skip_synth)
        except SystemExit as e:
            if e.code == EXIT_LOCKED:
                print("已在生成（locked）", file=sys.stderr)
                raise SystemExit(EXIT_LOCKED)
            raise
        print(json.dumps(state, ensure_ascii=False, indent=2))
        status = state.get("status")
        raise SystemExit(0 if status in ("ready", "degraded") else 1)

    if args.cmd == "synth":
        try:
            state = synth_brief(date=args.date)
        except SystemExit as e:
            if e.code == EXIT_LOCKED:
                print("已在生成（locked）", file=sys.stderr)
                raise SystemExit(EXIT_LOCKED)
            raise
        if state is None:
            print("无可合成的来源（sources 缺失或为空）", file=sys.stderr)
            raise SystemExit(1)
        print(json.dumps(state, ensure_ascii=False, indent=2))
        status = state.get("status")
        raise SystemExit(0 if status in ("ready", "degraded") else 1)

    day = date_str(local_today(cfg.timezone))
    day_path = brief_dir(day)

    if args.cmd == "status":
        run_path = day_path / "run.json"
        if not run_path.exists():
            print(json.dumps({"date": day, "status": "missing"}))
            raise SystemExit(1)
        print(run_path.read_text(encoding="utf-8"))
        raise SystemExit(0)

    if args.cmd == "sections":
        brief_path = day_path / "brief.json"
        if not brief_path.exists():
            print("[]")
            raise SystemExit(1)
        data = json.loads(brief_path.read_text(encoding="utf-8"))
        for s in data.get("sections", []):
            print(f"- {s.get('id')}: {s.get('title')} [{s.get('status')}]")
        raise SystemExit(0)

    if args.cmd == "open":
        day_path.mkdir(parents=True, exist_ok=True)
        subprocess.run(["open", str(day_path)], check=False)
        raise SystemExit(0)

    if args.cmd == "install-schedule":
        raise SystemExit(install_schedule())

    if args.cmd == "uninstall-schedule":
        raise SystemExit(uninstall_schedule())

    if args.cmd == "kickstart":
        raise SystemExit(kickstart())

    parser.error(f"unknown command {args.cmd}")


if __name__ == "__main__":
    main()
