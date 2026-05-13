#!/usr/bin/env bash
# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Configures and builds a Release (arm64) .app bundle into
# build/arm64-release. Use --debug for an unoptimized build with full
# symbol info.

set -euo pipefail

PRESET="arm64-release"
if [[ "${1:-}" == "--debug" ]]; then PRESET="arm64-debug"; fi
if [[ "${1:-}" == "--tsan"  ]]; then PRESET="arm64-debug-tsan"; fi
if [[ "${1:-}" == "--asan"  ]]; then PRESET="arm64-debug-asan"; fi

PORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PORT_ROOT}"

# Locate Qt 6.10+: prefer an explicit QT_ROOT, fall back to brew prefix.
if [[ -z "${QT_ROOT:-}" ]]; then
    if command -v brew >/dev/null 2>&1; then
        QT_ROOT="$(brew --prefix qt 2>/dev/null || true)"
    fi
fi
if [[ -n "${QT_ROOT:-}" ]]; then
    export CMAKE_PREFIX_PATH="${QT_ROOT}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
fi

cmake --preset "${PRESET}"
cmake --build --preset "${PRESET}" --parallel

echo
echo "Built: ${PORT_ROOT}/build/${PRESET}/MorseRunner.app"
