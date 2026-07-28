from __future__ import annotations

import os
import sys
from pathlib import Path

APP_SUPPORT = Path.home() / "Library" / "Application Support" / "MorningBrief"
BRIEFS_DIR = APP_SUPPORT / "briefs"
LOGS_DIR = APP_SUPPORT / "logs"
AGENT_WS_DIR = APP_SUPPORT / "agent-workspaces"
ASSISTANT_DIR = APP_SUPPORT / "assistant"
SESSION_SUMMARIES_DIR = ASSISTANT_DIR / "session-summaries"
WORK_LEDGER_DB = APP_SUPPORT / "work-ledger.sqlite3"
CONFIG_DIR = Path.home() / ".config" / "morning-brief"
CONFIG_PATH = CONFIG_DIR / "config.toml"

PACKAGE_DIR = Path(__file__).resolve().parent
PACKAGE_ROOT = PACKAGE_DIR.parent


def _resource_root() -> Path:
    """Directory that holds `skills/` + `schemas/` for this install.

    Preference order:
    1. ``MORNINGBRIEF_ROOT`` override (App Support wrapper sets this)
    2. Editable checkout repo root (when running from source tree)
    3. Application Support runtime (menu-bar / TCC-safe install)
    4. Packaged schemas next to this module
    """
    override = os.environ.get("MORNINGBRIEF_ROOT")
    if override:
        return Path(override)

    # Editable: .../packages/morningbrief/morningbrief/paths.py → repo root
    maybe_repo = Path(__file__).resolve().parents[3]
    if (
        (maybe_repo / "skills").is_dir()
        and (maybe_repo / "schemas").is_dir()
        and (maybe_repo / "packages" / "morningbrief").is_dir()
    ):
        return maybe_repo

    runtime = APP_SUPPORT / "runtime"
    if (runtime / "skills").is_dir() or (runtime / "schemas").is_dir():
        return runtime

    if (PACKAGE_DIR / "schemas").is_dir():
        return PACKAGE_DIR

    return runtime


REPO_ROOT = _resource_root()


def _schemas_dir() -> Path:
    for candidate in (
        REPO_ROOT / "schemas",
        PACKAGE_DIR / "schemas",
        APP_SUPPORT / "runtime" / "schemas",
    ):
        if candidate.is_dir():
            return candidate
    return PACKAGE_DIR / "schemas"


SCHEMAS_DIR = _schemas_dir()


def brief_dir(date_str: str) -> Path:
    return BRIEFS_DIR / date_str


def ensure_app_dirs() -> None:
    for p in (BRIEFS_DIR, LOGS_DIR, AGENT_WS_DIR, ASSISTANT_DIR, SESSION_SUMMARIES_DIR, CONFIG_DIR):
        p.mkdir(parents=True, exist_ok=True)


def resolve_python() -> str:
    """Interpreter that has morningbrief deps.

    Prefer the interpreter currently running this module (App Support venv or
    editable checkout). Falling back to a bare ``python3`` is what made doctor
    report missing deps after the TCC-safe install.
    """
    return sys.executable
