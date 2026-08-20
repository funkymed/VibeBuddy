#!/usr/bin/env bash
#
# make-dmg.sh — wrap dist/VibeBuddy.app into a distributable disk image.
#
# `hdiutil` alone, no third-party tooling: a DMG is a filesystem with an alias
# to /Applications, and every "DMG builder" on the shelf adds a dependency to
# produce the same two files.
#
#   ./scripts/make-dmg.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="VibeBuddy"
APP="dist/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/$APP_NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -d "$APP" ] || { echo "✗ $APP absent — lance ./scripts/build.sh d'abord." >&2; exit 1; }

echo "▸ $APP_NAME $VERSION"

cp -R "$APP" "$STAGE/"
# The drag-and-drop target. A symlink, so the image stays a few kilobytes
# heavier rather than carrying a copy of the folder.
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

SIZE="$(du -h "$DMG" | cut -f1)"
echo "✓ $DMG ($SIZE)"

# Verify the image mounts and carries the app, rather than trusting that
# `hdiutil` said nothing. A DMG that fails to mount is the one failure mode
# nobody notices until a user reports it.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -quiet
if [ -x "$MOUNT/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
    echo "✓ image montée, exécutable présent"
else
    echo "✗ l'image monte mais l'app est incomplète" >&2
    hdiutil detach "$MOUNT" -quiet
    exit 1
fi
hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT" 2>/dev/null || true
