#!/usr/bin/env bash
#
# make-cask.sh — write the Homebrew cask for the current version.
#
#   ./scripts/make-cask.sh [output.rb]
#
# Prints the cask to stdout by default, or writes it where told. The tap lives
# in its own repository — github.com/funkymed/homebrew-vibebuddy — so this
# script produces the file and never pushes it: the version being released and
# the tap being updated are two decisions, and conflating them is how a tap
# ends up pointing at a DMG nobody uploaded.
#
# What the cask buys is `zap` and a one-line install. It does **not** solve
# Gatekeeper: Homebrew *adds* the quarantine attribute rather than removing it
# — verified on 2026-08-21 with `xattr -l`, which showed "Homebrew Cask" as the
# writer, and `--no-quarantine` was removed in Homebrew 6. Users run
# `xattr -dr com.apple.quarantine` once, or the app gets notarised.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-}"
VERSION="$(grep -m1 'static let number' Sources/VibeBuddy/AppVersion.swift | sed 's/.*"\(.*\)".*/\1/')"
DMG="dist/VibeBuddy-${VERSION}.dmg"
REPO="funkymed/VibeBuddy"

[ -f "$DMG" ] || {
  echo "✗ $DMG introuvable — lance d'abord: make dmg" >&2
  exit 1
}

# The checksum is of the file that will actually be downloaded. Computing it
# from anything but the released DMG is how a cask ships a hash nobody can
# reproduce.
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

CASK=$(cat <<RUBY
cask "vibebuddy" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/${REPO}/releases/download/v#{version}/VibeBuddy-#{version}.dmg"
  name "VibeBuddy"
  desc "Turns the MacBook notch into a dashboard for your coding agents"
  homepage "https://github.com/${REPO}"

  depends_on macos: ">= :sonoma"

  app "VibeBuddy.app"

  # Signed with a stable self-signed identity, not notarised. Homebrew adds the
  # quarantine attribute, and Homebrew 6 dropped --no-quarantine. After
  # installing:
  #   xattr -dr com.apple.quarantine /Applications/VibeBuddy.app

  zap trash: [
    "~/Library/Application Support/VibeBuddy",
    "~/Library/Preferences/fr.funkylab.vibebuddy.plist",
    "~/.vibebuddy",
  ]
end
RUBY
)

if [ -n "$OUT" ]; then
  mkdir -p "$(dirname "$OUT")"
  printf '%s\n' "$CASK" > "$OUT"
  echo "✓ $OUT — version $VERSION, sha256 ${SHA:0:12}…"
else
  printf '%s\n' "$CASK"
fi
