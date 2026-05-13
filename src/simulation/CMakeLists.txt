# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Group 1 (C.G1): pure-function building blocks — Messages enum +
# templates, NumberFormat::nrAsText, IsMyCall.
# Group 2 (C.G2): Station hierarchy + DxOperator FSM.
# Group 3 (C.G3) adds Qrm/Qrn/StationCollection; Group 4 (C.G4) the
# Contest orchestrator.
add_library(mr_simulation STATIC
    CallsignDb.cpp
    CallsignDb.h
    CallsignSource.cpp
    CallsignSource.h
    Contest.cpp
    Contest.h
    DxOperator.cpp
    DxOperator.h
    DxStation.cpp
    DxStation.h
    Engine.h
    IsMyCall.cpp
    IsMyCall.h
    Messages.cpp
    Messages.h
    MyStation.cpp
    MyStation.h
    NumberFormat.cpp
    NumberFormat.h
    QrmStation.cpp
    QrmStation.h
    QrnStation.cpp
    QrnStation.h
    Station.cpp
    Station.h
    StationCollection.cpp
    StationCollection.h
)
target_include_directories(mr_simulation PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(mr_simulation PUBLIC mr_core mr_dsp mr_scoring)
morserunner_apply_warnings(mr_simulation)
