# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

add_library(mr_core STATIC
    Constants.h
    DelphiColor.h
    License.h
    Logging.cpp
    Logging.h
    Random.cpp
    Random.h
    Theme.cpp
    Theme.h
    ThreadNames.cpp
    ThreadNames.h
    WavWriter.cpp
    WavWriter.h
)
target_include_directories(mr_core PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(mr_core PUBLIC Qt6::Core Qt6::Gui)
set_target_properties(mr_core PROPERTIES AUTOMOC ON)
morserunner_apply_warnings(mr_core)
