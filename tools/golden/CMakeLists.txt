# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Reference-data dump tools for the Swift port. Build and run them with
# tools/golden/regenerate.sh, which compiles with -ffp-contract=off so the
# C++ float math matches Swift (no fused multiply-add) and writes into
# Swift/Sources/MRTestSupport/Fixtures.

function(mr_add_golden name)
    add_executable(${name} ${name}.cpp golden_io.h)
    target_link_libraries(${name} PRIVATE mr_core mr_dsp mr_scoring mr_simulation)
    morserunner_apply_warnings(${name})
endfunction()

mr_add_golden(golden_random)
mr_add_golden(golden_dsp)
mr_add_golden(golden_scoring)
mr_add_golden(golden_sim)
target_compile_definitions(golden_sim PRIVATE MR_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
