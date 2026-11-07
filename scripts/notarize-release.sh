#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${STILL_SIGN_IDENTITY:?Set STILL_SIGN_IDENTITY to your Developer ID Application identity}"
: "${STILL_NOTARY_PROFILE:?Set STILL_NOTARY_PROFILE to a notarytool keychain profile}"
[[ "$STILL_SIGN_IDENTITY" != "-" ]] || { echo 'Developer ID signing is required.' >&2; exit 1; }
security find-identity -v -p codesigning | grep -F -- "$STILL_SIGN_IDENTITY" >/dev/null || { echo 'Signing identity not available.' >&2; exit 1; }
bash scripts/check.sh
bash scripts/build-app.sh
APP="$PWD/build/Still Music.app"
ZIP="$PWD/build/Still-Music-notarization.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$STILL_NOTARY_PROFILE" --wait --output-format json > build/notarization-app.json
/usr/bin/plutil -extract status raw -o - build/notarization-app.json | grep -qx Accepted
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
bash scripts/build-dmg.sh --skip-build
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/StillMusic")
DMG="$PWD/build/Still-Music-$VERSION-$ARCH.dmg"
codesign --force --timestamp --sign "$STILL_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$STILL_NOTARY_PROFILE" --wait --output-format json > build/notarization-dmg.json
/usr/bin/plutil -extract status raw -o - build/notarization-dmg.json | grep -qx Accepted
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
printf 'Notarized release: %s\n' "$DMG"
