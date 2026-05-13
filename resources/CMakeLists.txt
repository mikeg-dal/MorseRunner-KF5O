# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Compile the .qrc into a tiny static helper library. AUTORCC handles
# generation; the qrc itself enumerates the resource files (Readme.txt
# today; more under /docs and /icons later). Modules that need resource
# access link mr_resources transitively.
add_library(mr_resources STATIC ${CMAKE_CURRENT_SOURCE_DIR}/MorseRunner.qrc)
set_target_properties(mr_resources PROPERTIES AUTORCC ON LINKER_LANGUAGE CXX)
target_link_libraries(mr_resources PUBLIC Qt6::Core)
