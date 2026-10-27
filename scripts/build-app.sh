#!/bin/bash
# Builds the app and assembles build/LightsOut.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/LightsOut.app"

echo "▸ Building app ($CONFIG)"
swift build --package-path "$ROOT" -c "$CONFIG"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

echo "▸ Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/LightsOut" "$APP/Contents/MacOS/LightsOut"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

ICON="$ROOT/Resources/AppIcon.icns"
if [ ! -f "$ICON" ] || [ "$ROOT/scripts/make-icon.swift" -nt "$ICON" ]; then
    echo "▸ Rendering icon"
    swift "$ROOT/scripts/make-icon.swift" "$ROOT/Resources"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

if [ "$CONFIG" = "release" ]; then strip -x "$APP/Contents/MacOS/LightsOut"; fi

# Development builds are signed with your Apple Development certificate when there is one, so the
# Accessibility grant survives rebuilds; otherwise ad hoc. make release re-signs with a Developer ID.
IDENTITY="${DEV_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --deep --options runtime --sign "${IDENTITY:--}" --timestamp=none "$APP" >/dev/null
echo "✓ $(du -sh "$APP" | cut -f1)  $APP (signed: ${IDENTITY:-ad hoc})"
