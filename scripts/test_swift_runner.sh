#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${TMPDIR:-/tmp}/morningbrief-swift-test-cache"
BINARY="${TMPDIR:-/tmp}/morningbrief-runner-smoke"

mkdir -p "$CACHE"
xcrun swiftc \
  -parse-as-library \
  -target arm64-apple-macos14.0 \
  -module-cache-path "$CACHE" \
  "$ROOT/apps/MorningBrief/Sources/BriefModels.swift" \
  "$ROOT/apps/MorningBrief/Sources/BriefctlRunner.swift" \
  "$ROOT/apps/MorningBrief/Tests/BriefctlRunnerSmoke.swift" \
  -o "$BINARY"
"$BINARY"
