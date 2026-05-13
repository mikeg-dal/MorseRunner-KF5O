# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# AudioEngine (QAudioSink on its dedicated QThread) and SimulationWorker
# (Phase-B smoke-test producer) plus the SPSC ring buffer wrapper. The
# real Contest-engine consumer lands in Phase C; SimulationWorker is
# replaced wholesale at that point but the threading topology stays.
add_library(mr_audio STATIC
    AudioEngine.cpp
    AudioEngine.h
    AudioFrame.h
    AudioRing.h
    SimulationWorker.cpp
    SimulationWorker.h
)
target_include_directories(mr_audio PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(mr_audio
    PUBLIC mr_core mr_dsp mr_simulation Qt6::Multimedia Qt6::Core
    PRIVATE mr_third_party::readerwriterqueue)
set_target_properties(mr_audio PROPERTIES AUTOMOC ON)
morserunner_apply_warnings(mr_audio)
