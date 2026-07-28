#!/usr/bin/env bash
# Build MorningBrief.app and install it to ~/Applications.
#
# Never leave a runnable .app under Downloads/Desktop/Documents — macOS TCC
# prompts on every launch when LaunchServices still indexes a bundle there
# (even a deleted path can linger until unregistered).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apps/MorningBrief/Sources"
APP_DEST="${MORNINGBRIEF_APP_DEST:-$HOME/Applications/MorningBrief.app}"
# Ephemeral build dir — do not persist a second .app under App Support (LS indexes it).
BUILD_ROOT="${MORNINGBRIEF_APP_BUILD_ROOT:-${TMPDIR:-/tmp}/morningbrief-app-build-$$}"
OUT="$BUILD_ROOT/MorningBrief.app"
BIN="$OUT/Contents/MacOS/MorningBrief"
SDK="$(xcrun --show-sdk-path)"
MODULE_CACHE="${TMPDIR:-/tmp}/morningbrief-swift-module-cache"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
cleanup() { rm -rf "$BUILD_ROOT"; }
trap cleanup EXIT

case "$APP_DEST" in
  "$HOME/Downloads"|"$HOME/Downloads"/*|"$HOME/Desktop"|"$HOME/Desktop"/*|"$HOME/Documents"|"$HOME/Documents"/*)
    echo "Refusing to install MorningBrief.app into a TCC-protected folder: $APP_DEST" >&2
    exit 1
    ;;
esac

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$MODULE_CACHE"

cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>MorningBrief</string>
	<key>CFBundleIdentifier</key>
	<string>com.yupeng.MorningBrief</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>MorningBrief</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "→ Compiling with SDK $SDK"
# Nested Sources/** (Architecture/, Features/, Shell/)
SWIFT_SOURCES=()
while IFS= read -r line; do
  SWIFT_SOURCES+=("$line")
done < <(find "$SRC" -name '*.swift' | sort)
if [[ ${#SWIFT_SOURCES[@]} -eq 0 ]]; then
  echo "No Swift sources under $SRC" >&2
  exit 1
fi
xcrun swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -o "$BIN" \
  "${SWIFT_SOURCES[@]}"

chmod +x "$BIN"
codesign --force --deep --sign - "$OUT" 2>/dev/null || true

echo "→ Installing $APP_DEST"
mkdir -p "$(dirname "$APP_DEST")"
"$LSREGISTER" -u "$ROOT/dist/MorningBrief.app" 2>/dev/null || true
"$LSREGISTER" -u "$HOME/Library/Application Support/MorningBrief/build/MorningBrief.app" 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/MorningBrief/build/MorningBrief.app"
rm -rf "$APP_DEST"
cp -R "$OUT" "$APP_DEST"
codesign --force --deep --sign - "$APP_DEST" 2>/dev/null || true
"$LSREGISTER" -f "$APP_DEST" 2>/dev/null || true

STALE_DIST="$ROOT/dist/MorningBrief.app"
if [[ -d "$STALE_DIST" ]]; then
  echo "→ Removing stale checkout app at $STALE_DIST (avoids Downloads TCC)"
  rm -rf "$STALE_DIST"
fi

mkdir -p "$ROOT/dist"
cat > "$ROOT/dist/README.txt" <<EOF
MorningBrief.app is installed at:
  $APP_DEST

Do not keep a .app under Downloads/Desktop/Documents — macOS will prompt for
folder access on every launch.
EOF

echo "→ Installed $APP_DEST"
ls -la "$APP_DEST/Contents/MacOS/MorningBrief"
