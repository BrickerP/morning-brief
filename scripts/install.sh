#!/usr/bin/env bash
# Install briefctl for terminal + desktop app use.
#
# The desktop app must NOT invoke a binary / skill that lives under Downloads /
# Desktop / Documents — macOS TCC prompts on every launch. Runtime assets always
# live under Application Support.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packages/morningbrief"
PY="${MORNINGBRIEF_PYTHON:-python3}"

if ! command -v "$PY" >/dev/null 2>&1; then
  echo "Need python3 (≥3.11). Install via Homebrew: brew install python@3.13" >&2
  exit 1
fi

case "$ROOT" in
  "$HOME/Downloads"|"$HOME/Downloads"/*|"$HOME/Desktop"|"$HOME/Desktop"/*|"$HOME/Documents"|"$HOME/Documents"/*)
    echo "⚠ Repo is under a macOS TCC-protected folder ($ROOT)."
    echo "  The desktop app will use Application Support runtime (no Downloads access)."
    echo "  Prefer launching: ~/Applications/MorningBrief.app"
    ;;
esac

SUPPORT="$HOME/Library/Application Support/MorningBrief"
RUNTIME="$SUPPORT/runtime"
BIN_DIR="$SUPPORT/bin"
mkdir -p "$SUPPORT" "$RUNTIME" "$BIN_DIR"

echo "→ Syncing skills + schemas into $RUNTIME (TCC-safe)"
rm -rf "$RUNTIME/skills" "$RUNTIME/schemas"
cp -R "$ROOT/skills" "$RUNTIME/skills"
cp -R "$ROOT/schemas" "$RUNTIME/schemas"

echo "→ Creating Application Support venv at $RUNTIME/venv"
"$PY" -m venv "$RUNTIME/venv"
# shellcheck disable=SC1091
source "$RUNTIME/venv/bin/activate"
python -m pip install -U pip wheel
# Non-editable install copies code into site-packages so the app never
# reads the repo tree (which may live under Downloads).
python -m pip install "$PKG"

cat > "$BIN_DIR/briefctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SUPPORT="${MORNINGBRIEF_SUPPORT:-$HOME/Library/Application Support/MorningBrief}"
export MORNINGBRIEF_ROOT="$SUPPORT/runtime"
PY="$SUPPORT/runtime/venv/bin/python"
if [[ ! -x "$PY" ]]; then
  echo "MorningBrief runtime missing at $PY — re-run scripts/install.sh" >&2
  exit 1
fi
exec "$PY" -m morningbrief "$@"
EOF
chmod +x "$BIN_DIR/briefctl"
echo "$BIN_DIR/briefctl" > "$SUPPORT/briefctl.path"
echo "→ Pinned app CLI at $SUPPORT/briefctl.path → $BIN_DIR/briefctl"

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
ln -sfn "$BIN_DIR/briefctl" "$BIN/briefctl"
echo "→ Linked $BIN/briefctl → $BIN_DIR/briefctl"

# Rewrite config skill_script paths that still point at a TCC-protected checkout.
CONFIG="$HOME/.config/morning-brief/config.toml"
if [[ -f "$CONFIG" ]]; then
  ROOT="$ROOT" RUNTIME_SKILLS="$RUNTIME/skills" python - <<'PY'
from pathlib import Path
import os
import re

config = Path.home() / ".config/morning-brief/config.toml"
text = config.read_text(encoding="utf-8")
runtime_skills = Path(os.environ["RUNTIME_SKILLS"]).resolve()
repo_skills = (Path(os.environ["ROOT"]) / "skills").resolve()
home = Path.home()
protected_prefixes = (
    str(home / "Downloads") + "/",
    str(home / "Desktop") + "/",
    str(home / "Documents") + "/",
    str(repo_skills) + "/",
)

def rewrite(match: re.Match[str]) -> str:
    raw = match.group(1)
    path = str(Path(raw).expanduser())
    if not any(path.startswith(prefix) for prefix in protected_prefixes):
        return match.group(0)
    parts = Path(path).parts
    if "skills" not in parts:
        return match.group(0)
    suffix = Path(*parts[parts.index("skills") + 1 :])
    return f'skill_script = "{runtime_skills / suffix}"'

new_text, count = re.subn(
    r'^skill_script\s*=\s*"([^"]+)"',
    rewrite,
    text,
    flags=re.MULTILINE,
)
if new_text != text:
    config.write_text(new_text, encoding="utf-8")
    print(f"→ Rewrote skill_script paths in {config} ({count} lines)")
else:
    print("→ Config skill paths already TCC-safe (or unchanged)")
PY
fi

# Keep a repo-local editable venv for developers working from the checkout.
echo "→ Refreshing repo-local editable venv at $PKG/.venv (dev / terminal from checkout)"
"$PY" -m venv "$PKG/.venv"
# shellcheck disable=SC1091
source "$PKG/.venv/bin/activate"
python -m pip install -U pip wheel
python -m pip install -e "$PKG"

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

echo "Done. Ensure $BIN is on PATH (zsh: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc)"
echo "Menu-bar app resolves briefctl via: $SUPPORT/briefctl.path"
