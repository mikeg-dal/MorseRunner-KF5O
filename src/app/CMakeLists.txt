# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# AppController wires SimulationWorker + AudioEngine + MainWindow together
# during the application bootstrap. main.cpp is linked into the executable
# target directly (not into this library) because qt_add_executable expects
# it there for the MOC main-window discovery.
add_library(mr_app STATIC
    AppController.cpp
    AppController.h
)
target_include_directories(mr_app PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(mr_app
    PUBLIC mr_core mr_ui mr_audio mr_simulation mr_persistence
           Qt6::Core Qt6::Widgets
    PRIVATE mr_third_party::readerwriterqueue)
set_target_properties(mr_app PROPERTIES AUTOMOC ON)
morserunner_apply_warnings(mr_app)
