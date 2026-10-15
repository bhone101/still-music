#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-taglib.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --product StillMusic --scratch-path .build
APP="$PWD/build/Still Music.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --scratch-path .build --show-bin-path)"
cp "$BIN_DIR/StillMusic" "$APP/Contents/MacOS/StillMusic"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/.build/StillMusic.iconset"
iconutil -c icns "$PWD/.build/StillMusic.iconset" -o "$APP/Contents/Resources/StillRing.icns"
mkdir -p "$APP/Contents/Resources/ThirdPartyLicenses"
cp Vendor/taglib-2.2.1/COPYING.MPL "$APP/Contents/Resources/ThirdPartyLicenses/TagLib-MPL.txt"
cp Vendor/taglib-2.2.1/3rdparty/utfcpp/LICENSE "$APP/Contents/Resources/ThirdPartyLicenses/utfcpp.txt"
cp Vendor/README.md "$APP/Contents/Resources/ThirdPartyLicenses/NOTICE.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/ThirdPartyLicenses/Still-NOTICES.md"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '\nBuilt %s\n' "$APP"
