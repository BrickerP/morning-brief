from __future__ import annotations

import importlib.util
import shutil
import sys
from pathlib import Path

from morningbrief.config import load_config
from morningbrief.paths import CONFIG_PATH, SCHEMAS_DIR, ensure_app_dirs, resolve_python
from morningbrief.proc import run_cmd
from morningbrief.synth import check_agent_auth


def run_doctor() -> int:
    ensure_app_dirs()
    cfg = load_config()
    ok = True
    print("Morning Brief doctor")
    print(f"  config: {CONFIG_PATH} ({'ok' if CONFIG_PATH.exists() else 'MISSING'})")
    if not CONFIG_PATH.exists():
        ok = False

    py = resolve_python()
    print(f"  python: {py}")
    for mod in ("feedparser", "requests", "bs4"):
        check = run_cmd([py, "-c", f"import {mod if mod != 'bs4' else 'bs4'}"], timeout_s=20)
        status = "ok" if check.returncode == 0 else "MISSING"
        print(f"  dep {mod}: {status}")
        if check.returncode != 0:
            ok = False
    js = run_cmd([py, "-c", "import jsonschema"], timeout_s=20)
    print(f"  dep jsonschema: {'ok' if js.returncode == 0 else 'optional (fallback validator)'}")

    for src in cfg.sources:
        path = Path(src.skill_script)
        exists = path.exists()
        print(f"  source {src.id}: {path} ({'ok' if exists else 'MISSING'})")
        if src.enabled and not exists:
            ok = False

    for name in (
        "source_result.schema.json",
        "brief_document.schema.json",
        "run_state.schema.json",
    ):
        p = SCHEMAS_DIR / name
        print(f"  schema {name}: {'ok' if p.exists() else 'MISSING'}")
        if not p.exists():
            ok = False

    agent = shutil.which(cfg.agent_bin) or cfg.agent_bin
    agent_path = Path(agent) if Path(agent).exists() else shutil.which(cfg.agent_bin)
    print(f"  agent bin: {agent_path or cfg.agent_bin}")
    auth = check_agent_auth(cfg.agent_bin)
    print(f"  agent auth: {'ok' if auth else 'NOT LOGGED IN (synth will degrade)'}")
    # Auth failure is warning for doctor exit — still fail closed if agent binary missing
    if not shutil.which(cfg.agent_bin) and not Path(cfg.agent_bin).exists():
        print("  ERROR: agent binary not found")
        ok = False

    print(f"  python executable used by adapters: {py}")
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1
