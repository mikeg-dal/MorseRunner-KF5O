#!/usr/bin/env bash
# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Builds a distributable .dmg from the notarized .app with the
# standard drag-to-Applications layout:
#   - MorseRunner.app icon on the left
#   - Applications symlink on the right
#   - Icon view, no toolbar/sidebar, sensible window size
#
# Pipeline:
#   1. Stage .app + Applications symlink in a temp folder
#   2. hdiutil create UDRW (writable) from the stage
#   3. Mount, apply window geometry via AppleScript, detach
#   4. Convert UDRW → UDZO (compressed read-only)
#   5. Sign + notarize + staple the final DMG
#
# Run after scripts/sign_and_notarize.sh.

set -euo pipefail

PORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="${MR_PRESET:-arm64-release}"
BUILD="${PORT_ROOT}/build/${PRESET}"
APP="${BUILD}/MorseRunner.app"

if [[ ! -d "${APP}" ]]; then
    echo "error: ${APP} does not exist." >&2
    echo "Run scripts/build.sh + scripts/sign_and_notarize.sh first." >&2
    exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "${APP}/Contents/Info.plist")"
DMG="${BUILD}/MorseRunner-${VERSION}.dmg"
DMG_RW="${BUILD}/MorseRunner-${VERSION}-rw.dmg"
VOLNAME="Morse Runner ${VERSION}"
STAGE="${BUILD}/dmg-stage"

# Tidy up any prior attempt — re-running the script must be idempotent.
rm -f "${DMG}" "${DMG_RW}"
rm -rf "${STAGE}"

echo "[1/6] Staging .app + Applications symlink"
mkdir -p "${STAGE}"
# Copy preserves the deep signatures from sign_and_notarize.sh.
ditto "${APP}" "${STAGE}/MorseRunner.app"
ln -s /Applications "${STAGE}/Applications"

echo "[2/6] Creating writable image"
# UDRW = read-write, mountable so we can drop a .DS_Store with window
# geometry. Size auto-calculated by hdiutil from staged content.
hdiutil create \
    -volname "${VOLNAME}" \
    -srcfolder "${STAGE}" \
    -ov \
    -format UDRW \
    "${DMG_RW}" >/dev/null

echo "[3/6] Mounting and applying window layout via AppleScript"
# Mount with -nobrowse so Finder doesn't pop the window during scripting.
ATTACH_OUT="$(hdiutil attach -nobrowse -readwrite "${DMG_RW}")"
# hdiutil lists "device  fstype  mount-point" separated by tabs. The
# mount point may contain spaces (it does here — "Morse Runner 1.68"),
# so we can't use awk's whitespace tokenizer. sed extracts everything
# after the literal "/Volumes/" up to end of line.
MOUNT_POINT="$(echo "${ATTACH_OUT}" | grep -E '/Volumes/' | sed -E 's/^.*	(\/Volumes\/.*)$/\1/' | tail -1)"
if [[ -z "${MOUNT_POINT}" || ! -d "${MOUNT_POINT}" ]]; then
    echo "error: failed to determine mount point from hdiutil output" >&2
    echo "${ATTACH_OUT}" >&2
    exit 1
fi
echo "      mounted at ${MOUNT_POINT}"

# AppleScript instructs Finder to:
#   - open the volume window
#   - switch to icon view
#   - hide the toolbar and sidebar (cleaner first-time view)
#   - set window bounds, icon size, and per-icon positions
#   - close the window so Finder writes .DS_Store
# The 1-second delays give Finder time to commit each state change to
# .DS_Store; without them the file is sometimes written stale.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLNAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "MorseRunner.app" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Force a sync so the .DS_Store is flushed to the image before detach.
sync
sleep 1

echo "[4/6] Detaching writable image"
hdiutil detach "${MOUNT_POINT}" >/dev/null

echo "[5/6] Converting to compressed read-only UDZO"
hdiutil convert "${DMG_RW}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG}" >/dev/null
rm -f "${DMG_RW}"

# Re-sign the DMG with the Developer ID (optional but conventional for
# Developer-ID distribution); notarize and staple it so Gatekeeper can
# validate offline when users download via Safari.
if [[ -n "${MR_SIGN_IDENTITY:-}" ]]; then
    echo "[6/6] codesign + notarize + staple DMG"
    codesign --force --sign "${MR_SIGN_IDENTITY}" "${DMG}"
    if [[ -n "${MR_NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "${DMG}" \
            --keychain-profile "${MR_NOTARY_PROFILE}" \
            --wait
        xcrun stapler staple "${DMG}"
        xcrun stapler validate "${DMG}"
    else
        echo "      (MR_NOTARY_PROFILE not set; skipping notarization)"
    fi
else
    echo "[6/6] (MR_SIGN_IDENTITY not set; skipping DMG sign + notarize)"
fi

# Cleanup the staging dir; the .app inside the DMG is the canonical copy.
rm -rf "${STAGE}"

echo
echo "DMG ready: ${DMG}"
