#!/bin/bash
# Builds build/LightsOut.app. Pass --install to copy it into /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/LightsOut.app"

swift build -c release

if [[ ! -f Resources/AppIcon.icns ]]; then
    swift scripts/make-icon.swift Resources
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/LightsOut" "$APP/Contents/MacOS/LightsOut"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable signing identity keeps the Accessibility grant valid across rebuilds; fall back to ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x LightsOut 2>/dev/null && sleep 1 || true
    rm -rf /Applications/LightsOut.app
    cp -R "$APP" /Applications/
    open /Applications/LightsOut.app
    echo "Installed and launched /Applications/LightsOut.app"
fi
