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
  -framework ServiceManagement \
  -framework UniformTypeIdentifiers

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Code signing. Signing with a STABLE local identity (the self-signed "ahdishot-dev" cert) keeps
# the Screen Recording (TCC) grant alive across rebuilds: TCC keys the grant off the app's
# designated requirement, which references this cert's leaf hash. Ad-hoc signing ("-") instead
# changes the cdhash on every build, so macOS treats each rebuild as a new app and drops the grant.
# If the cert isn't installed, we fall back to ad-hoc (see HANDOVER §"Local signing" to recreate it).
SIGN_ID="ahdishot-dev"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  echo "Code signing with '$SIGN_ID'…"
  codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "⚠️  Signing identity '$SIGN_ID' not found — falling back to ad-hoc."
  echo "    (Screen Recording permission will reset on each rebuild; see HANDOVER to recreate the cert.)"
  codesign --force --sign - "$APP"
fi

echo "Verifying architecture…"
file "$APP/Contents/MacOS/ahdishot"

echo ""
echo "Built: $APP"
echo "Run with: open \"$APP\"   (or)   \"$APP/Contents/MacOS/ahdishot\""
