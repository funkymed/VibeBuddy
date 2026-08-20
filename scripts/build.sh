#!/usr/bin/env bash
#
# build.sh — assemble VibeBuddy.app from the SwiftPM products.
#
# Produces dist/VibeBuddy.app containing both executables, an Info.plist, an
# icon, and a signature. Universal when Xcode is present, single-arch otherwise.
#
#   ./scripts/build.sh              build, sign with the stable identity
#   ./scripts/build.sh --no-sign    build only (the app will not survive a copy)
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="VibeBuddy"
BUNDLE_ID="fr.funkylab.vibebuddy"
VERSION="$(grep -m1 'static let number' Sources/VibeBuddy/AppVersion.swift | sed 's/.*"\(.*\)".*/\1/')"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="dist"
APP="$DIST/$APP_NAME.app"
SIGN_IDENTITY="${VIBEBUDDY_SIGN_IDENTITY:-VibeBuddy Self-Signed}"
DO_SIGN=1
[ "${1:-}" = "--no-sign" ] && DO_SIGN=0

echo "▸ $APP_NAME $VERSION (build $BUILD)"

# ── Compile ────────────────────────────────────────────────────────────────
#
# The universal build needs a full Xcode; Command Line Tools alone cannot do
# `--arch arm64 --arch x86_64`. The reference hides stderr here, which turns a
# real compile error into a silent single-arch fallback — so we keep the output
# and only fall back when Xcode itself is missing.
BIN_DIR=".build/apple/Products/Release"
if [ -d "$(xcode-select -p 2>/dev/null)/Platforms" ]; then
    echo "▸ build universel (arm64 + x86_64)"
    if ! swift build -c release --arch arm64 --arch x86_64; then
        echo "✗ la compilation universelle a échoué — ce n'est pas un problème d'outillage" >&2
        exit 1
    fi
else
    echo "▸ Xcode absent, build mono-architecture"
    swift build -c release
    BIN_DIR=".build/release"
fi

# ── Assemble ───────────────────────────────────────────────────────────────
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/"
# The hook is spawned by Claude Code on every tool call and must never link
# AppKit (decision D4). It ships inside the bundle so one install covers both.
[ -f "$BIN_DIR/vibe-hook" ] && cp "$BIN_DIR/vibe-hook" "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Accessory app: no Dock icon, no menu bar. The pill is the whole UI. -->
    <key>LSUIElement</key><true/>
    <!-- Counts directly against the energy budget on dual-GPU machines. -->
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
</dict>
</plist>
PLIST

if [ -x scripts/generate-icon.swift ] || [ -f scripts/generate-icon.swift ]; then
    echo "▸ icône"
    swift scripts/generate-icon.swift "$DIST/AppIcon.iconset" >/dev/null
    iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$DIST/AppIcon.iconset"
fi

# ── Sign ───────────────────────────────────────────────────────────────────
#
# No ad-hoc fallback. A fallback turns a signing failure into a silently
# degraded build whose identity changes on every run, and an identity that
# changes is what revokes granted permissions on every update.
if [ "$DO_SIGN" = 1 ]; then
    if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
        echo "✗ identité de signature « $SIGN_IDENTITY » introuvable." >&2
        echo "  Crée-la une fois avec ./scripts/make-identity.sh, ou passe --no-sign." >&2
        exit 1
    fi
    echo "▸ signature « $SIGN_IDENTITY »"
    for binary in "$APP/Contents/MacOS/"*; do
        codesign --force --options runtime --timestamp=none \
            --sign "$SIGN_IDENTITY" "$binary"
    done
    codesign --force --options runtime --timestamp=none \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
fi

SIZE="$(du -sh "$APP" | cut -f1)"
echo "✓ $APP ($SIZE)"
