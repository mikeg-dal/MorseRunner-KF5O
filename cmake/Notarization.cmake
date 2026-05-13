# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Notarization itself runs out-of-band via scripts/sign_and_notarize.sh —
# it requires Apple's notary servers and a keychain profile, neither of
# which belongs inside the build graph. This module exists only to keep
# the include site in the top-level CMakeLists.txt symmetric with the
# other macOS-specific modules and to document where the operation lives.
#
# To notarize a Release build:
#   ./scripts/sign_and_notarize.sh
#
# Required env vars (read by the script, not by CMake):
#   MR_SIGN_IDENTITY        e.g. "Developer ID Application: Mike Garcia (TEAMID)"
#   MR_NOTARY_PROFILE       keychain profile name from `xcrun notarytool store-credentials`
