# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Audio DSP module. Sources are pure C++ (no Qt types in the headers) so
# the simulation engine and unit tests can use them without dragging Qt
# headers in. Implementation files include core/Constants.h transitively.
add_library(mr_dsp STATIC
    BlackmanHarris.cpp
    BlackmanHarris.h
    ComplexBuf.h
    MorseKeyer.cpp
    MorseKeyer.h
    MorseTable.cpp
    MorseTable.h
    MovingAverage.cpp
    MovingAverage.h
    PingPongFilter.cpp
    PingPongFilter.h
    Agc.cpp
    Agc.h
    Modulator.cpp
    Modulator.h
    QuickAverage.cpp
    QuickAverage.h
    Qsb.cpp
    Qsb.h
)
target_include_directories(mr_dsp PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(mr_dsp PUBLIC mr_core)
morserunner_apply_warnings(mr_dsp)
