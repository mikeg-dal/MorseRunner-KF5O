# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# GoogleTest is fetched via FetchContent so the build is self-contained.
# The DSP determinism tests need richer float assertions than Qt Test
# provides; GoogleTest's FLOAT_NEAR / DoubleNear are what's expected by
# tests/dsp/test_*.cpp written in Phase B.
include(FetchContent)
set(FETCHCONTENT_QUIET FALSE)

FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
)
# Use shared CRT settings (no effect on Apple).
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_subdirectory(dsp)
add_subdirectory(audio)
add_subdirectory(simulation)
add_subdirectory(scoring)
