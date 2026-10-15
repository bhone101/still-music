#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  "") bash scripts/build-app.sh ;;
  --skip-build) ;;
  *) echo 'Usage: bash scripts/build-dmg.sh [--skip-build]' >&2; exit 1 ;;
esac

APP="$PWD/build/Still Music.app"
codesign --verify --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/StillMusic")
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported package architecture: $ARCH" >&2; exit 1 ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid bundle version' >&2; exit 1; }

STAGING=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Still Music.app"
ln -s /Applications "$STAGING/Applications"
cp Resources/Install.txt "$STAGING/Read Me.txt"
DMG="$PWD/build/Still-Music-$VERSION-$ARCH.dmg"
hdiutil create -volname 'Still Music' -srcfolder "$STAGING" -format UDZO -fs HFS+ -ov "$DMG"
hdiutil verify "$DMG"
(
  cd build
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)
printf '\nCreated %s\n' "$DMG"
