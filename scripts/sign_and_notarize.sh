#!/usr/bin/env bash
# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Full Developer-ID signing + notarization pipeline for a Release build.
# Run scripts/build.sh first.
#
# Required environment variables:
#   MR_SIGN_IDENTITY    e.g. "Developer ID Application: Mike Garcia (TEAMID)"
#   MR_NOTARY_PROFILE   keychain profile name created with:
#                       xcrun notarytool store-credentials
#
# The script runs macdeployqt (to embed Qt frameworks into the bundle),
# then deep-signs every framework + the bundle itself with --options runtime
# --timestamp and the hardened-runtime entitlements, submits the zipped
# bundle to Apple's notary service, and staples the resulting ticket back
# onto the .app.

set -euo pipefail

: "${MR_SIGN_IDENTITY:?MR_SIGN_IDENTITY must be set, e.g. 'Developer ID Application: Mike Garcia (TEAMID)'}"
: "${MR_NOTARY_PROFILE:?MR_NOTARY_PROFILE must be set; see xcrun notarytool store-credentials}"

PORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="${MR_PRESET:-arm64-release}"
BUILD="${PORT_ROOT}/build/${PRESET}"
APP="${BUILD}/MorseRunner.app"
ENTITLEMENTS="${PORT_ROOT}/resources/MorseRunner.entitlements"
ZIP="${BUILD}/MorseRunner.zip"

if [[ ! -d "${APP}" ]]; then
    echo "error: ${APP} does not exist. Run scripts/build.sh first." >&2
    exit 1
fi

# Locate macdeployqt next to the qmake we built against. macdeployqt
# copies Qt frameworks into the bundle, rewrites install names, and is the
# only supported way to ship a Qt app on macOS.
if [[ -z "${QT_ROOT:-}" ]]; then
    if command -v brew >/dev/null 2>&1; then
        QT_ROOT="$(brew --prefix qt 2>/dev/null || true)"
    fi
fi
MACDEPLOYQT="${QT_ROOT:-}/bin/macdeployqt"
if [[ ! -x "${MACDEPLOYQT}" ]]; then
    echo "error: macdeployqt not found at ${MACDEPLOYQT}." >&2
    echo "Set QT_ROOT or install Qt via Homebrew." >&2
    exit 1
fi

echo "[1/7] macdeployqt: embedding Qt frameworks"
"${MACDEPLOYQT}" "${APP}" -always-overwrite

# Deep-sign each framework first. The bundle signature wraps everything,
# but Apple's notary rejects nested code that lacks --options runtime, so
# we sign inside-out.
echo "[2/7] codesign: hardening embedded dylibs + frameworks"
# Qt 6.10 ships its multimedia stack with FFmpeg .dylib siblings of the
# .framework bundles — both must be deep-signed inside-out before the
# enclosing .app signature wraps them. We sign in this order:
#   1. PlugIns/**/*.dylib  — Qt QPA plugins (platforms/, imageformats/,
#      multimedia/, networkinformation/, styles/, tls/, etc.). macdeployqt
#      copies these from Qt's distribution and they keep their Qt Company
#      team signature (A5GTH44LYL). Our entitlements enforce library
#      validation (disable-library-validation = false), so the loader
#      rejects nested code signed by a non-matching team and aborts in
#      QGuiApplicationPrivate::createPlatformIntegration. Re-signing
#      these with our identity replaces the Qt Company signature and
#      satisfies library validation.
#   2. Frameworks/*.dylib  — FFmpeg dylibs alongside the Qt frameworks.
#   3. Frameworks/*.framework — Qt frameworks (with entitlements).
# Libraries don't carry entitlements — only the main executable does.
echo "      PlugIns/"
find "${APP}/Contents/PlugIns" -name "*.dylib" -print0 |
    while IFS= read -r -d '' f; do
        echo "        $(basename "$(dirname "${f}")")/$(basename "${f}")"
        codesign --force --options runtime --timestamp \
            --sign "${MR_SIGN_IDENTITY}" \
            "${f}"
    done
echo "      Frameworks/ (dylibs)"
find "${APP}/Contents/Frameworks" -name "*.dylib" -print0 |
    while IFS= read -r -d '' f; do
        echo "        $(basename "${f}")"
        codesign --force --options runtime --timestamp \
            --sign "${MR_SIGN_IDENTITY}" \
            "${f}"
    done
echo "      Frameworks/ (frameworks)"
find "${APP}/Contents/Frameworks" -name "*.framework" -print0 |
    while IFS= read -r -d '' fw; do
        echo "        $(basename "${fw}")"
        codesign --force --options runtime --timestamp \
            --entitlements "${ENTITLEMENTS}" \
            --sign "${MR_SIGN_IDENTITY}" \
            "${fw}"
    done

echo "[3/7] codesign: app bundle"
codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${MR_SIGN_IDENTITY}" \
    "${APP}"

echo "[4/7] codesign --verify"
codesign --verify --deep --strict --verbose=2 "${APP}"

echo "[5/7] notarytool submit (this may take several minutes)"
ditto -c -k --keepParent "${APP}" "${ZIP}"
xcrun notarytool submit "${ZIP}" \
    --keychain-profile "${MR_NOTARY_PROFILE}" \
    --wait

echo "[6/7] stapler staple"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

echo "[7/7] spctl assess (Gatekeeper acceptance check)"
spctl --assess --type execute --verbose=4 "${APP}"

echo
echo "Signed, notarized, and stapled: ${APP}"
