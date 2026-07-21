#!/usr/bin/env bash
# One-shot local deploy: CLI + menu bar app + briefctl path pin.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> 1/4 Install briefctl (venv + ~/.local/bin)"
bash "$ROOT/scripts/install.sh"

SUPPORT="$HOME/Library/Application Support/MorningBrief"
mkdir -p "$SUPPORT"
echo "$ROOT/bin/briefctl" > "$SUPPORT/briefctl.path"
echo "→ Pinned briefctl at $SUPPORT/briefctl.path"

echo "==> 2/4 Doctor"
export PATH="$HOME/.local/bin:$PATH"
"$ROOT/bin/briefctl" doctor || true

echo "==> 3/4 Build menu bar app (needs macOS + Xcode CLT)"
if ! xcrun --show-sdk-path >/dev/null 2>&1; then
  echo "⚠ No macOS SDK — skip app build. CLI still works: briefctl run"
else
  bash "$ROOT/scripts/build_app.sh"
  echo "==> 4/4 Launch app"
  open "$ROOT/dist/MorningBrief.app"
fi

cat <<EOF

✓ Local deploy ready

  briefctl doctor
  briefctl run --skip-synth    # fetch only
  briefctl run                 # + agent synth (optional: agent login)
  briefctl install-schedule    # weekdays/daily 07:30 launchd

Menu bar: look for 「晨报」 (or Control Center overflow).
Config: ~/.config/morning-brief/config.toml
Briefs: ~/Library/Application Support/MorningBrief/briefs/

EOF
