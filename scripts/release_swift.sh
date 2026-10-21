#!/usr/bin/env bash
# Morse Runner — native Swift port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Build, sign, notarize and zip the Swift/AppKit app.
#
#   export MR_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
#   export MR_TEAM_ID=<TEAMID>
#   export MR_NOTARY_PROFILE=<notarytool keychain profile>
#   scripts/release_swift.sh
#
# Output: dist/MorseRunner-<version>-macOS.zip (universal, stapled).

set -euo pipefail

: "${MR_SIGN_IDENTITY:?set MR_SIGN_IDENTITY to your Developer ID Application identity}"
: "${MR_TEAM_ID:?set MR_TEAM_ID to your Apple team ID}"
: "${MR_NOTARY_PROFILE:?set MR_NOTARY_PROFILE to a notarytool keychain profile}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_DIR="$ROOT/Swift"
BUILD_DIR="$SWIFT_DIR/.build-release"
APP="$BUILD_DIR/Build/Products/Release/MorseRunner.app"
DIST="$ROOT/dist"

cd "$SWIFT_DIR"
xcodegen generate

echo "==> Release build (signed)"
xcodebuild -project MorseRunner.xcodeproj -scheme MorseRunner -configuration Release \
    -derivedDataPath "$BUILD_DIR" clean build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$MR_SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$MR_TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    | grep -E "error|BUILD (SUCCEEDED|FAILED)" || true
[[ -d "$APP" ]] || { echo "build failed: $APP missing" >&2; exit 1; }

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow; then
    echo "get-task-allow entitlement present; notarization would fail" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SUBMIT_ZIP="$BUILD_DIR/notarize.zip"
ZIP="$DIST/MorseRunner-$VERSION-macOS.zip"

echo "==> Notarize"
rm -f "$SUBMIT_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMIT_ZIP"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$MR_NOTARY_PROFILE" --wait
rm -f "$SUBMIT_ZIP"

echo "==> Staple and check Gatekeeper"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"

echo "==> Zip"
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
echo "Done: $ZIP"
