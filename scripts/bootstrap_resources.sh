#!/usr/bin/env bash
# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copies data and license artifacts from the original Delphi repo into this
# port's resources/ tree. Run once after cloning; safe to re-run.
#
# After this step, the macos-qt/ directory is self-contained and may be
# relocated to its own repository. The Pascal source is intentionally NOT
# copied — only the binary callsign database, license, and end-user README.

set -euo pipefail

PORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGINAL_ROOT="$(cd "${PORT_ROOT}/.." && pwd)"

copy_if_present() {
    local src="$1" dst="$2"
    if [[ -f "${src}" ]]; then
        mkdir -p "$(dirname "${dst}")"
        cp -p "${src}" "${dst}"
        echo "  copied: ${src} -> ${dst}"
    else
        echo "  skipped (not present): ${src}"
    fi
}

echo "Bootstrapping resources from ${ORIGINAL_ROOT}"
copy_if_present "${ORIGINAL_ROOT}/Master.dta" "${PORT_ROOT}/resources/data/Master.dta"
copy_if_present "${ORIGINAL_ROOT}/LICENSE"    "${PORT_ROOT}/LICENSE"
copy_if_present "${ORIGINAL_ROOT}/Readme.txt" "${PORT_ROOT}/resources/docs/Readme.txt"
echo "Done."
