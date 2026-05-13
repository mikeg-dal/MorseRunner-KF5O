#!/usr/bin/env bash
# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Runs the standard Gatekeeper-acceptance checks against a signed bundle.

set -euo pipefail

PORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="${MR_PRESET:-arm64-release}"
APP="${PORT_ROOT}/build/${PRESET}/MorseRunner.app"

if [[ ! -d "${APP}" ]]; then
    echo "error: ${APP} does not exist." >&2; exit 1
fi

echo "── codesign --verify"
codesign --verify --deep --strict --verbose=2 "${APP}"
echo

echo "── codesign -dvvv"
codesign -dvvv "${APP}"
echo

echo "── spctl --assess"
spctl --assess --type execute --verbose=4 "${APP}"
echo

echo "── stapler validate"
xcrun stapler validate "${APP}" || echo "(stapler ticket missing — run sign_and_notarize.sh)"
