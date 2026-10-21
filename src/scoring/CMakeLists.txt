# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

add_library(mr_scoring STATIC
    CallToScore.cpp
    CallToScore.h
    Crc32.cpp
    Crc32.h
    ExtractPrefix.cpp
    ExtractPrefix.h
    QsoLog.cpp
    QsoLog.h
)
target_include_directories(mr_scoring PUBLIC ${CMAKE_SOURCE_DIR}/src)
# mr_dsp gives us mr::dsp::encodeMessage which CallToScore consumes.
target_link_libraries(mr_scoring PUBLIC mr_core mr_dsp)
