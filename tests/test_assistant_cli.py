from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[1] / "packages" / "morningbrief"

# Drives cli.main() with app-support paths and the Claude projects root redirected
# into a tmp dir, and the agent invocation stubbed so no real `agent` CLI runs.
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
paths.ASSISTANT_DIR = root / "assistant"
paths.SESSION_SUMMARIES_DIR = root / "assistant" / "session-summaries"
paths.WORK_LEDGER_DB = root / "work-ledger.sqlite3"
paths.CONFIG_DIR = root / "config"
paths.CONFIG_PATH = paths.CONFIG_DIR / "config.toml"

import morningbrief.config as config
config.CONFIG_PATH = paths.CONFIG_PATH

import morningbrief.work_ledger as work_ledger
original_ledger = work_ledger.WorkLedger

class IsolatedWorkLedger(original_ledger):
    def __init__(self, *args, **kwargs):
        kwargs.setdefault("db_path", paths.WORK_LEDGER_DB)
        kwargs.setdefault("briefs_dir", paths.BRIEFS_DIR)
        super().__init__(*args, **kwargs)

work_ledger.WorkLedger = IsolatedWorkLedger

import morningbrief.session_assistant as sa
sa.WorkLedger = IsolatedWorkLedger
# Point the Claude projects root at our fixture and stub the agent runner so
# `analyze` exercises the CLI dispatch without a real agent subprocess.
projects_root = Path(os.environ["MORNINGBRIEF_TEST_PROJECTS"])
_orig_find = sa.find_claude_session
_orig_locate_list = sa.list_recent_sessions
_orig_analyze_confirmed = sa.analyze_confirmed_session
_orig_analyze = sa.analyze_claude_session
_orig_summarize = sa.summarize_session
_orig_ensure = sa.ensure_session_summaries
sa.find_claude_session = lambda tail, **kw: _orig_find(
    tail, claude_projects_root=projects_root,
    command_runner=kw.get("command_runner", sa.run_cmd),
)
sa.locate_claude_session = sa.find_claude_session
sa.list_recent_sessions = lambda *a, **kw: _orig_locate_list(
    *a, **{**kw, "claude_projects_root": projects_root,
           "summaries_dir": paths.SESSION_SUMMARIES_DIR}
)

def _fake_agent(args, *, timeout_s, env=None):
    from morningbrief.proc import ProcResult
    payload = json.loads(os.environ["MORNINGBRIEF_TEST_AGENT_JSON"])
    return ProcResult(0, json.dumps(payload, ensure_ascii=False), "")

sa.analyze_confirmed_session = lambda sf, **kw: _orig_analyze_confirmed(
    sf, **{**kw, "claude_projects_root": projects_root, "agent_runner": _fake_agent}
)
sa.analyze_claude_session = lambda tail, **kw: _orig_analyze(
    tail, **{**kw, "claude_projects_root": projects_root, "agent_runner": _fake_agent}
)
sa.summarize_session = lambda sf, **kw: _orig_summarize(
    sf, **{**kw, "claude_projects_root": projects_root,
           "summaries_dir": paths.SESSION_SUMMARIES_DIR,
           "agent_workspace_dir": paths.AGENT_WS_DIR,
           "agent_runner": _fake_agent}
)
sa.ensure_session_summaries = lambda *a, **kw: _orig_ensure(
    *a, **{**kw, "claude_projects_root": projects_root,
           "summaries_dir": paths.SESSION_SUMMARIES_DIR,
           "agent_workspace_dir": paths.AGENT_WS_DIR,
           "agent_runner": _fake_agent}
)

import morningbrief.cli as cli
cli.find_claude_session = sa.find_claude_session
cli.list_recent_sessions = sa.list_recent_sessions
cli.analyze_confirmed_session = sa.analyze_confirmed_session
cli.analyze_claude_session = sa.analyze_claude_session
cli.summarize_session = sa.summarize_session
cli.ensure_session_summaries = sa.ensure_session_summaries

cli.main(json.loads(sys.argv[1]))
"""


def _write_session(root: Path, project: str, session_id: str, lines: list[dict]) -> Path:
    project_dir = root / project
    project_dir.mkdir(parents=True, exist_ok=True)
    path = project_dir / f"{session_id}.jsonl"
    path.write_text(
        "\n".join(json.dumps(line, ensure_ascii=False) for line in lines) + "\n",
        encoding="utf-8",
    )
    return path


def _run_cli(
    root: Path,
    projects_root: Path,
    *args: str,
    stdin: str | None = None,
    agent_json: dict | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["MORNINGBRIEF_TEST_ROOT"] = str(root)
    env["MORNINGBRIEF_TEST_PROJECTS"] = str(projects_root)
    env["PYTHONPATH"] = str(PACKAGE_ROOT)
    env["MORNINGBRIEF_TEST_AGENT_JSON"] = json.dumps(agent_json or {"summary": "ok", "proposals": []})
    return subprocess.run(
        [sys.executable, "-c", CLI_DRIVER, json.dumps(list(args))],
        cwd=PACKAGE_ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=60,
        input=stdin,
        check=False,
    )


def test_cli_sessions_lists_recent_parents(tmp_path: Path) -> None:
    projects = tmp_path / "projects"
    older = _write_session(
        projects, "-proj-a", "11111111-1111-1111-1111-111111111111",
        [{"type": "summary", "summary": "旧会话"}],
    )
    newer = _write_session(
        projects, "-proj-b", "22222222-2222-2222-2222-222222222222",
        [{"type": "user", "message": {"content": "帮我排查支付回调"}}],
    )
    os.utime(older, (1000, 1000))
    os.utime(newer, (2000, 2000))

    result = _run_cli(tmp_path / "as", projects, "assistant", "sessions", "--limit", "5")
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    ids = [s["id"] for s in payload["sessions"]]
    assert ids == [
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    ]
    assert payload["sessions"][0]["preview"] == "帮我排查支付回调"
    assert payload["sessions"][0]["summary"] is None
    assert payload["sessions"][0]["summary_status"] == "pending"
    # Opener-only Claude summary records are not used as list preview anymore.
    assert payload["sessions"][1]["preview"] == ""


def test_cli_summarize_persists_and_skips_cache_hit(tmp_path: Path) -> None:
    projects = tmp_path / "projects"
    _write_session(
        projects, "-proj", "55555555-5555-5555-5555-555555555555",
        [{"type": "user", "message": {"content": "总结这条会话"}}],
    )
    agent_json = {"summary": "排查支付回调，结论已落地，仍需生产回归。"}
    first = _run_cli(
        tmp_path / "as",
        projects,
        "assistant",
        "summarize",
        "--limit",
        "3",
        agent_json=agent_json,
    )
    assert first.returncode == 0, first.stderr
    payload = json.loads(first.stdout)
    assert payload["summarized"] == 1
    assert payload["skipped"] == 0
    assert payload["sessions"][0]["summary"] == agent_json["summary"]
    assert payload["sessions"][0]["summary_status"] == "ready"

    second = _run_cli(
        tmp_path / "as",
        projects,
        "assistant",
        "summarize",
        "--limit",
        "3",
        agent_json={"summary": "不应再次调用"},
    )
    assert second.returncode == 0, second.stderr
    again = json.loads(second.stdout)
    assert again["summarized"] == 0
    assert again["skipped"] == 1
    assert again["sessions"][0]["summary"] == agent_json["summary"]

    listing = _run_cli(tmp_path / "as", projects, "assistant", "sessions", "--limit", "3")
    assert listing.returncode == 0, listing.stderr
    listed = json.loads(listing.stdout)
    assert listed["sessions"][0]["summary"] == agent_json["summary"]
    assert listed["sessions"][0]["summary_status"] == "ready"


def test_cli_locate_matches_pasted_ending(tmp_path: Path) -> None:
    projects = tmp_path / "projects"
    session_id = "33333333-3333-3333-3333-333333333333"
    _write_session(
        projects, "-proj", session_id,
        [{"message": "最终结论：支付回调已修复，仍需生产回归一次。"}],
    )
    result = _run_cli(
        tmp_path / "as", projects,
        "assistant", "locate", "--input", "-",
        stdin="最终结论：支付回调已修复，仍需生产回归一次。\n",
    )
    assert result.returncode == 0, result.stderr
    match = json.loads(result.stdout)
    assert match["id"] == session_id
    assert match["source_file"].endswith(f"{session_id}.jsonl")


def test_cli_analyze_session_file_skips_locate(tmp_path: Path) -> None:
    projects = tmp_path / "projects"
    session_id = "44444444-4444-4444-4444-444444444444"
    session_file = _write_session(
        projects, "-proj", session_id,
        [{"type": "user", "message": {"content": "生产环境支付回归"}}],
    )
    agent_json = {
        "summary": "会话已定位支付问题，仍需生产回归。",
        "todo_matches": [],
        "proposals": [],
    }
    result = _run_cli(
        tmp_path / "as", projects,
        "assistant", "analyze", "--session-file", str(session_file),
        agent_json=agent_json,
    )
    assert result.returncode == 0, result.stderr
    analysis = json.loads(result.stdout)
    assert analysis["session"]["id"] == session_id
    assert analysis["summary"] == "会话已定位支付问题，仍需生产回归。"


def test_cli_analyze_session_file_rejects_out_of_tree_path(tmp_path: Path) -> None:
    projects = tmp_path / "projects"
    projects.mkdir(parents=True, exist_ok=True)
    outsider = tmp_path / "elsewhere.jsonl"
    outsider.write_text("{}\n", encoding="utf-8")
    result = _run_cli(
        tmp_path / "as", projects,
        "assistant", "analyze", "--session-file", str(outsider),
    )
    assert result.returncode == 2
    payload = json.loads(result.stdout)
    assert payload["error"]["type"] == "SessionAssistantError"
