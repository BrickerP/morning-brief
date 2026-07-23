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

TODO_SKILL="$ROOT/skills/todo"
for SKILL_HOME in \
  "$HOME/.codex/skills" \
  "$HOME/.claude/skills" \
  "$HOME/.cursor/skills"; do
  mkdir -p "$SKILL_HOME"
  TODO_LINK="$SKILL_HOME/todo"
  if [[ -e "$TODO_LINK" && ! -L "$TODO_LINK" ]]; then
    echo "Refusing to replace non-symlink skill at $TODO_LINK" >&2
    exit 1
  fi
  ln -sfn "$TODO_SKILL" "$TODO_LINK"
  echo "→ Linked $TODO_LINK → $TODO_SKILL"
done

# Pin for the menu bar app (portable; no hardcoded user paths in Swift)
SUPPORT="$HOME/Library/Application Support/MorningBrief"
mkdir -p "$SUPPORT"
echo "$ROOT/bin/briefctl" > "$SUPPORT/briefctl.path"

echo "Done. Ensure $BIN is on PATH (zsh: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc)"
