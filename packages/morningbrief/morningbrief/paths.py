from __future__ import annotations

import os
from pathlib import Path

APP_SUPPORT = Path.home() / "Library" / "Application Support" / "MorningBrief"
BRIEFS_DIR = APP_SUPPORT / "briefs"
LOGS_DIR = APP_SUPPORT / "logs"
AGENT_WS_DIR = APP_SUPPORT / "agent-workspaces"
WORK_LEDGER_DB = APP_SUPPORT / "work-ledger.sqlite3"
CONFIG_DIR = Path.home() / ".config" / "morning-brief"
CONFIG_PATH = CONFIG_DIR / "config.toml"

REPO_ROOT = Path(__file__).resolve().parents[3]
SCHEMAS_DIR = REPO_ROOT / "schemas"
PACKAGE_ROOT = Path(__file__).resolve().parents[1]


def brief_dir(date_str: str) -> Path:
    return BRIEFS_DIR / date_str


def ensure_app_dirs() -> None:
    for p in (BRIEFS_DIR, LOGS_DIR, AGENT_WS_DIR, CONFIG_DIR):
        p.mkdir(parents=True, exist_ok=True)


def resolve_python() -> str:
    # Prefer package venv, then env/python3.
    # Do NOT Path.resolve() — that follows the venv python symlink to the
    # base interpreter and drops site-packages.
    candidates = [
        PACKAGE_ROOT / ".venv" / "bin" / "python",
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    return os.environ.get("MORNINGBRIEF_PYTHON", "python3")
