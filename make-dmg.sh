#!/bin/bash
# Packages ahdishot into a drag-to-install disk image: build/ahdishot-<version>.dmg.
# Runs build.sh first. The image isn't notarized (no Apple Developer ID), so people who download it
# click "Open Anyway" once on first launch; see README "Install".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/ahdishot.app"

"$ROOT/build.sh"

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/ahdishot-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ahdishot.app"      # ditto keeps the code signature intact
ln -s /Applications "$STAGE/Applications"

echo "Creating disk image…"
hdiutil create -volname "ahdishot $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo ""
echo "Built: $DMG ($(du -h "$DMG" | cut -f1))"
