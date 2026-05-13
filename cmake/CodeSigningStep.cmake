# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Invoked in CMake script mode from CodeSigning.cmake. Variables expected:
#   TARGET_BUNDLE   absolute path to the built .app
#   ENTITLEMENTS    absolute path to the entitlements plist

if(NOT DEFINED ENV{MR_SIGN_IDENTITY})
    # No identity configured -> nothing to do. The full distribution
    # pipeline lives in scripts/sign_and_notarize.sh; this in-build step
    # exists only to keep developer builds runnable under the hardened
    # runtime when an identity is available.
    return()
endif()

execute_process(
    COMMAND codesign
        --force
        --options runtime
        --timestamp=none
        --entitlements "${ENTITLEMENTS}"
        --sign "$ENV{MR_SIGN_IDENTITY}"
        "${TARGET_BUNDLE}"
    RESULT_VARIABLE rc)

if(NOT rc EQUAL 0)
    message(WARNING "codesign (developer) failed; running unsigned.")
endif()
