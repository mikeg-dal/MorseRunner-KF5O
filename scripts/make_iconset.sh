#!/usr/bin/env bash
# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Generates resources/icons/MorseRunner.icns from a single high-resolution
# source: either the vector master (resources/icons/MorseRunner.svg, rendered
# per size with rsvg-convert so small slots stay crisp) or a 1024x1024 PNG. The iconset directory is preserved next to the
# .icns so designers can regenerate it without rerunning sips for each size.

set -euo pipefail

SRC="${1:-}"
if [[ -z "${SRC}" || ! -f "${SRC}" ]]; then
    echo "usage: $0 path/to/MorseRunner.svg|MorseRunner-1024.png" >&2
    exit 1
fi

PORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="${PORT_ROOT}/resources/icons/MorseRunner.iconset"
ICNS="${PORT_ROOT}/resources/icons/MorseRunner.icns"

# Start clean so stale non-standard slots never leak into the .icns.
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

# Standard iconset sizes per Apple Human Interface Guidelines. Each non-1x
# slot has a paired @2x retina rendering.
sizes=(16 32 32 64 128 256 256 512 512 1024)
names=(
    "icon_16x16.png"
    "icon_16x16@2x.png"
    "icon_32x32.png"
    "icon_32x32@2x.png"
    "icon_128x128.png"
    "icon_128x128@2x.png"
    "icon_256x256.png"
    "icon_256x256@2x.png"
    "icon_512x512.png"
    "icon_512x512@2x.png"
)

for i in "${!sizes[@]}"; do
    if [[ "${SRC}" == *.svg ]]; then
        rsvg-convert -w "${sizes[i]}" -h "${sizes[i]}" "${SRC}" -o "${ICONSET}/${names[i]}"
    else
        sips -z "${sizes[i]}" "${sizes[i]}" "${SRC}" --out "${ICONSET}/${names[i]}" >/dev/null
    fi
done

iconutil -c icns "${ICONSET}" -o "${ICNS}"
echo "Wrote ${ICNS}"
