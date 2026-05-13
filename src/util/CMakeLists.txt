# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Phase A: header-only placeholder. Module fills in during Phase B–F.
add_library(mr_util INTERFACE)
target_include_directories(mr_util INTERFACE ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(mr_util INTERFACE Qt6::Core)
