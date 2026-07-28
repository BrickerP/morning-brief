#!/usr/bin/env bash
# One-shot local deploy: CLI runtime (App Support) + desktop app (~/Applications).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> 1/4 Install briefctl runtime (Application Support + ~/.local/bin)"
bash "$ROOT/scripts/install.sh"

echo "==> 2/4 Doctor"
export PATH="$HOME/.local/bin:$PATH"
briefctl doctor || true

echo "==> 3/4 Build + install desktop app to ~/Applications (needs macOS + Xcode CLT)"
if ! xcrun --show-sdk-path >/dev/null 2>&1; then
  echo "⚠ No macOS SDK — skip app build. CLI still works: briefctl run"
else
  bash "$ROOT/scripts/build_app.sh"
  echo "==> 4/4 Launch ~/Applications/MorningBrief.app"
  # Launch from / so `open` does not stamp Downloads into the app's PWD.
  cd / && open "$HOME/Applications/MorningBrief.app"
fi

cat <<EOF

✓ Local deploy ready

  briefctl doctor
  briefctl run --skip-synth    # fetch only
  briefctl run                 # + agent synth (optional: agent login)
  briefctl install-schedule    # weekdays/daily 07:30 launchd

Menu bar: open ~/Applications/MorningBrief.app (not dist/ under Downloads).
CLI pin:  ~/Library/Application Support/MorningBrief/briefctl.path
Config:   ~/.config/morning-brief/config.toml
Briefs:   ~/Library/Application Support/MorningBrief/briefs/

EOF
