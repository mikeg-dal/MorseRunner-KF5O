# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Each subdirectory defines one static module library. They are linked
# together by the top-level MorseRunner executable target. The split
# matches the architecture in docs/architecture.md and isolates audio /
# simulation / UI so each can be unit-tested in headless mode.
add_subdirectory(core)
add_subdirectory(util)
add_subdirectory(dsp)
add_subdirectory(scoring)
add_subdirectory(simulation)
add_subdirectory(persistence)
add_subdirectory(audio)
add_subdirectory(ui)
add_subdirectory(app)
