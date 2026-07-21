#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packages/morningbrief"
PY="${MORNINGBRIEF_PYTHON:-python3}"

if ! command -v "$PY" >/dev/null 2>&1; then
  echo "Need python3 (≥3.11). Install via Homebrew: brew install python@3.13" >&2
  exit 1
fi

echo "→ Creating venv at $PKG/.venv"
"$PY" -m venv "$PKG/.venv"
# shellcheck disable=SC1091
source "$PKG/.venv/bin/activate"
python -m pip install -U pip wheel
python -m pip install -e "$PKG"

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
ln -sfn "$ROOT/bin/briefctl" "$BIN/briefctl"
echo "→ Linked $BIN/briefctl → $ROOT/bin/briefctl"

# Pin for the menu bar app (portable; no hardcoded user paths in Swift)
SUPPORT="$HOME/Library/Application Support/MorningBrief"
mkdir -p "$SUPPORT"
echo "$ROOT/bin/briefctl" > "$SUPPORT/briefctl.path"

echo "Done. Ensure $BIN is on PATH (zsh: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc)"
