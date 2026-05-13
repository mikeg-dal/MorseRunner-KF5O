# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# morserunner_sign(<target>)
#
# Opt-in: attaches a post-build command that signs the bundle with the
# identity in the MR_SIGN_IDENTITY environment variable. If unset, this
# function is a no-op, so local Debug builds remain frictionless.
#
# Distribution-quality signing (macdeployqt + deep re-sign + entitlements)
# is the responsibility of scripts/sign_and_notarize.sh — running it from
# CMake is intentionally lightweight; we only ad-hoc sign so that the
# binary launches at all under the hardened runtime during development.
function(morserunner_sign target)
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND "${CMAKE_COMMAND}"
            -DTARGET_BUNDLE=$<TARGET_BUNDLE_DIR:${target}>
            -DENTITLEMENTS=${CMAKE_SOURCE_DIR}/resources/MorseRunner.entitlements
            -P ${CMAKE_SOURCE_DIR}/cmake/CodeSigningStep.cmake
        VERBATIM)
endfunction()
