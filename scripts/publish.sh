#!/bin/bash
# Publishes what make release built: the GitHub release with LightsOut.dmg, then the site,
# which carries the appcast. In that order, so apps never see an update they can't download yet.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$ROOT/build/LightsOut.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/build/LightsOut.app/Contents/Info.plist")"
NOTES="$ROOT/release-notes/$VERSION.md"

[ -f "$DMG" ] || { echo "Run make release first"; exit 1; }
grep -q "v$VERSION/LightsOut.dmg" "$ROOT/site/public/appcast.xml" || { echo "appcast.xml isn't for $VERSION; run make release"; exit 1; }

echo "▸ GitHub release v$VERSION"
{
    echo '**Download `LightsOut.dmg`, open it, and drag Lights Out to Applications.** Signed with a Developer ID and notarized by Apple.'
    echo
    cat "$NOTES"
    echo
    echo 'Requires macOS 14 Sonoma or later on Apple Silicon.'
} | gh release create "v$VERSION" "$DMG" --title "Lights Out ${VERSION%.0}" --notes-file - --target main

echo "▸ Deploying site and appcast"
(cd "$ROOT/site" && npx wrangler deploy)
echo "✓ Lights Out $VERSION is live"
