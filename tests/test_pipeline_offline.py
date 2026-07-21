"""Offline pipeline tests with stubbed adapters."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

from morningbrief.config import AppConfig, SourceConfig
from morningbrief.models import ChildStatus, ErrorInfo, SourceResult
from morningbrief.pipeline import brief_meta, run_pipeline


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


def test_partial_source_still_writes_brief(tmp_path: Path, monkeypatch):
    # Redirect app support into tmp
    import morningbrief.paths as paths
    import morningbrief.pipeline as pipeline

    monkeypatch.setattr(paths, "APP_SUPPORT", tmp_path / "as")
    monkeypatch.setattr(paths, "BRIEFS_DIR", tmp_path / "as" / "briefs")
    monkeypatch.setattr(paths, "LOGS_DIR", tmp_path / "as" / "logs")
    monkeypatch.setattr(paths, "AGENT_WS_DIR", tmp_path / "as" / "agent-workspaces")
    monkeypatch.setattr(pipeline, "brief_dir", lambda d: paths.BRIEFS_DIR / d)

    cfg = AppConfig(
        timezone="Asia/Shanghai",
        skip_synth=True,
        notify_on_degraded=False,
        sources=[
            SourceConfig(id="ai_daily", title="AI", skill_script="/dev/null"),
            SourceConfig(id="daily_read", title="Read", skill_script="/dev/null"),
        ],
    )

    def fake_fetch(src, local_date, python_bin):
        if src.id == "ai_daily":
            return _failed("ai_daily", "AI")
        return SourceResult(
            id="daily_read",
            title="Read",
            status="partial",
            items=[{"kind": "article", "title": "ok", "link": "https://x", "summary": "s"}],
            children=[
                ChildStatus(id="noahpinion", status="ok", item_count=1),
                ChildStatus(id="stratechery", status="failed", item_count=0, error=ErrorInfo("x", "down")),
            ],
            meta={"fetched_at": "t", "duration_ms": 1, "adapter_version": "0.1.0"},
        )

    with patch("morningbrief.pipeline.fetch_source", side_effect=fake_fetch):
        state = run_pipeline(date="2026-07-21", config=cfg, skip_synth=True)

    assert state["status"] in ("ready", "degraded")
    day = paths.BRIEFS_DIR / "2026-07-21"
    assert (day / "brief.json").exists()
    assert (day / "brief.md").exists()
    brief = json.loads((day / "brief.json").read_text(encoding="utf-8"))
    assert brief["sections"]
    assert any(s["id"] == "daily_read" for s in brief["sections"])


def test_brief_meta_injects_staleness():
    cfg = AppConfig(staleness_hours=48, timezone="Asia/Shanghai")
    meta = brief_meta("skipped", cfg)
    assert meta == {"synth": "skipped", "staleness_hours": 48, "timezone": "Asia/Shanghai"}
    meta_extra = brief_meta("degraded", cfg, synth_error="boom")
    assert meta_extra["synth"] == "degraded"
    assert meta_extra["staleness_hours"] == 48
    assert meta_extra["timezone"] == "Asia/Shanghai"
    assert meta_extra["synth_error"] == "boom"


def test_skip_synth_writes_staleness_and_skipped(tmp_path: Path, monkeypatch):
    import morningbrief.paths as paths
    import morningbrief.pipeline as pipeline

    monkeypatch.setattr(paths, "APP_SUPPORT", tmp_path / "as")
    monkeypatch.setattr(paths, "BRIEFS_DIR", tmp_path / "as" / "briefs")
    monkeypatch.setattr(paths, "LOGS_DIR", tmp_path / "as" / "logs")
    monkeypatch.setattr(paths, "AGENT_WS_DIR", tmp_path / "as" / "agent-workspaces")
    monkeypatch.setattr(pipeline, "brief_dir", lambda d: paths.BRIEFS_DIR / d)

    cfg = AppConfig(
        timezone="Asia/Shanghai",
        skip_synth=True,
        notify_on_degraded=False,
        staleness_hours=48,
        sources=[SourceConfig(id="ai_daily", title="AI", skill_script="/dev/null")],
    )

    with patch("morningbrief.pipeline.fetch_source", side_effect=lambda src, local_date, python_bin: _ok(src.id, src.title)):
        run_pipeline(date="2026-07-21", config=cfg, skip_synth=True)

    day = paths.BRIEFS_DIR / "2026-07-21"
    brief = json.loads((day / "brief.json").read_text(encoding="utf-8"))
    assert brief["meta"]["synth"] == "skipped"
    assert brief["meta"]["staleness_hours"] == cfg.staleness_hours == 48


def test_concurrent_lock(tmp_path: Path, monkeypatch):
    import morningbrief.paths as paths
    import morningbrief.pipeline as pipeline
    import morningbrief.lock as lockmod

    monkeypatch.setattr(paths, "APP_SUPPORT", tmp_path / "as")
    monkeypatch.setattr(paths, "BRIEFS_DIR", tmp_path / "as" / "briefs")
    monkeypatch.setattr(paths, "LOGS_DIR", tmp_path / "as" / "logs")
    monkeypatch.setattr(paths, "AGENT_WS_DIR", tmp_path / "as" / "agent-workspaces")
    monkeypatch.setattr(pipeline, "brief_dir", lambda d: paths.BRIEFS_DIR / d)

    day = paths.BRIEFS_DIR / "2026-07-21"
    day.mkdir(parents=True)
    # Hold live lock as current pid
    import json as _json
    import os

    (day / "run.lock").write_text(
        _json.dumps({"pid": os.getpid(), "run_id": "hold", "started_at": "2026-07-21T00:00:00Z"}),
        encoding="utf-8",
    )
    cfg = AppConfig(skip_synth=True, notify_on_degraded=False, sources=[])
    try:
        run_pipeline(date="2026-07-21", config=cfg, skip_synth=True)
        assert False, "expected SystemExit 75"
    except SystemExit as e:
        assert e.code == lockmod.EXIT_LOCKED


def test_locked_stub_preserves_terminal_run_json(tmp_path: Path, monkeypatch):
    import morningbrief.paths as paths
    import morningbrief.pipeline as pipeline
    import morningbrief.lock as lockmod

    monkeypatch.setattr(paths, "APP_SUPPORT", tmp_path / "as")
    monkeypatch.setattr(paths, "BRIEFS_DIR", tmp_path / "as" / "briefs")
    monkeypatch.setattr(paths, "LOGS_DIR", tmp_path / "as" / "logs")
    monkeypatch.setattr(paths, "AGENT_WS_DIR", tmp_path / "as" / "agent-workspaces")
    monkeypatch.setattr(pipeline, "brief_dir", lambda d: paths.BRIEFS_DIR / d)

    day = paths.BRIEFS_DIR / "2026-07-21"
    day.mkdir(parents=True)
    # A completed (ready) run.json already exists from an earlier run.
    terminal = {"date": "2026-07-21", "run_id": "done", "status": "ready", "items_hash": "abc"}
    (day / "run.json").write_text(json.dumps(terminal), encoding="utf-8")

    import os

    (day / "run.lock").write_text(
        json.dumps({"pid": os.getpid(), "run_id": "hold", "started_at": "2026-07-21T00:00:00Z"}),
        encoding="utf-8",
    )
    cfg = AppConfig(skip_synth=True, notify_on_degraded=False, sources=[])
    try:
        run_pipeline(date="2026-07-21", config=cfg, skip_synth=True)
        assert False, "expected SystemExit 75"
    except SystemExit as e:
        assert e.code == lockmod.EXIT_LOCKED

    # The terminal run.json must survive — no 'locked' stub clobber.
    preserved = json.loads((day / "run.json").read_text(encoding="utf-8"))
    assert preserved["status"] == "ready"
    assert preserved["run_id"] == "done"
