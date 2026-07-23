#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apps/MorningBrief/Sources"
OUT="$ROOT/dist/MorningBrief.app"
BIN="$OUT/Contents/MacOS/MorningBrief"
SDK="$(xcrun --show-sdk-path)"
MODULE_CACHE="${TMPDIR:-/tmp}/morningbrief-swift-module-cache"

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
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "→ Compiling with SDK $SDK"
xcrun swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -o "$BIN" \
  "$SRC"/*.swift

chmod +x "$BIN"
# Ad-hoc sign so Gatekeeper allows local launch
codesign --force --deep --sign - "$OUT" 2>/dev/null || true
echo "→ Built $OUT"
ls -la "$BIN"
