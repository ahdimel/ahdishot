#!/bin/bash
# Builds the native arm64 ahdishot.app bundle from the command line (no Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/ahdishot.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling (arm64, deployment target macOS 15)…"
swiftc -O \
  -target arm64-apple-macos15 \
  -o "$APP/Contents/MacOS/ahdishot" \
  "$ROOT"/Sources/*.swift \
  -framework Cocoa \
  -framework ScreenCaptureKit \
  -framework Carbon \
  -framework UniformTypeIdentifiers

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign so the bundle has a stable identity for TCC (Screen Recording) prompts.
echo "Ad-hoc code signing…"
codesign --force --sign - "$APP"

echo "Verifying architecture…"
file "$APP/Contents/MacOS/ahdishot"

echo ""
echo "Built: $APP"
echo "Run with: open \"$APP\"   (or)   \"$APP/Contents/MacOS/ahdishot\""
