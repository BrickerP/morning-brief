"""Tests for P3 notify-on-ready behavior (mocked notify, stubbed adapters)."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

from morningbrief.config import AppConfig, SourceConfig
from morningbrief.models import BriefSection, ErrorInfo, SourceResult
from morningbrief.pipeline import maybe_notify_ready, run_pipeline, synth_brief


def _redirect_paths(tmp_path: Path, monkeypatch) -> Path:
    import morningbrief.paths as paths
    import morningbrief.pipeline as pipeline

    monkeypatch.setattr(paths, "APP_SUPPORT", tmp_path / "as")
    monkeypatch.setattr(paths, "BRIEFS_DIR", tmp_path / "as" / "briefs")
    monkeypatch.setattr(paths, "LOGS_DIR", tmp_path / "as" / "logs")
    monkeypatch.setattr(paths, "AGENT_WS_DIR", tmp_path / "as" / "agent-workspaces")
    monkeypatch.setattr(pipeline, "brief_dir", lambda d: paths.BRIEFS_DIR / d)
    return paths.BRIEFS_DIR


def _ok(sid: str, title: str) -> SourceResult:
    return SourceResult(
        id=sid,
        title=title,
        status="ok",
        items=[{"kind": "article", "title": f"{title} item", "link": "https://example.com", "summary": "hi"}],
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )


def _failed(sid: str, title: str) -> SourceResult:
    return SourceResult(
        id=sid,
        title=title,
        status="failed",
        error=ErrorInfo("net", "offline"),
        meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
    )


def _cfg(**kw) -> AppConfig:
    base = dict(
        timezone="Asia/Shanghai",
        notify_on_degraded=False,
        sources=[SourceConfig(id="ai_daily", title="AI", skill_script="/dev/null")],
    )
    base.update(kw)
    return AppConfig(**base)


def _agent_sections() -> list[BriefSection]:
    return [
        BriefSection(
            id="ai_daily",
            title="AI",
            kind="news",
            body_md="synthesized body",
            source_ids=["ai_daily"],
            status="synthesized",
        ),
        BriefSection(
            id="tools",
            title="有趣的 AI 工具",
            kind="tools",
            body_md="tool one, tool two",
            source_ids=[],
            status="synthesized",
        ),
    ]


def test_ready_with_flag_notifies_once_and_persists(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg(notify_on_ready=True)

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731
    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth, patch("morningbrief.pipeline.notify") as mock_notify:
        synth.return_value = (_agent_sections(), None)
        state = run_pipeline(date="2026-07-21", config=cfg)

    assert state["status"] == "ready"
    assert mock_notify.call_count == 1
    title, message = mock_notify.call_args.args
    assert title == "Morning Brief"
    assert "2026-07-21" in message

    run = json.loads((briefs / "2026-07-21" / "run.json").read_text(encoding="utf-8"))
    assert run["notified_ready"] is True


def test_already_notified_run_skips_second_call(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg(notify_on_ready=True)
    day_dir = briefs / "2026-07-21"
    day_dir.mkdir(parents=True)

    run_state = {"status": "ready", "notified_ready": True}
    with patch("morningbrief.pipeline.notify") as mock_notify:
        maybe_notify_ready(cfg, "2026-07-21", day_dir, [_ok("ai_daily", "AI")], run_state)

    assert mock_notify.call_count == 0


def test_notify_on_ready_false_never_notifies(tmp_path: Path, monkeypatch):
    _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg(notify_on_ready=False)

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731
    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth, patch("morningbrief.pipeline.notify") as mock_notify:
        synth.return_value = (_agent_sections(), None)
        state = run_pipeline(date="2026-07-21", config=cfg)

    assert state["status"] == "ready"
    assert mock_notify.call_count == 0


def test_synth_brief_path_notifies_on_ready(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg(notify_on_ready=True)

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731
    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth, patch("morningbrief.pipeline.notify") as mock_notify:
        # Fetch-only run leaves sources on disk; skip_synth means degraded -> no notify.
        run_pipeline(date="2026-07-21", config=cfg, skip_synth=True)
        pre_synth_calls = mock_notify.call_count

        synth.return_value = (_agent_sections(), None)
        state = synth_brief(date="2026-07-21", config=cfg)

    assert state is not None and state["status"] == "ready"
    assert mock_notify.call_count == pre_synth_calls + 1
    run = json.loads((briefs / "2026-07-21" / "run.json").read_text(encoding="utf-8"))
    assert run["notified_ready"] is True


def test_degraded_path_does_not_notify_ready(tmp_path: Path, monkeypatch):
    briefs = _redirect_paths(tmp_path, monkeypatch)
    cfg = _cfg(notify_on_ready=True, notify_on_degraded=False)

    fetch = lambda src, local_date, python_bin: _ok(src.id, src.title)  # noqa: E731
    with patch("morningbrief.pipeline.fetch_source", side_effect=fetch), patch(
        "morningbrief.pipeline.synthesize"
    ) as synth, patch("morningbrief.pipeline.notify") as mock_notify:
        # Synthesis fails -> degraded status -> notify_on_ready must not fire.
        synth.return_value = (None, "boom")
        state = run_pipeline(date="2026-07-21", config=cfg)

    assert state["status"] == "degraded"
    assert mock_notify.call_count == 0
    run = json.loads((briefs / "2026-07-21" / "run.json").read_text(encoding="utf-8"))
    assert "notified_ready" not in run
