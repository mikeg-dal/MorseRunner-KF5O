# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

function(mr_add_dsp_test name)
    add_executable(${name} ${name}.cpp)
    target_link_libraries(${name} PRIVATE mr_dsp mr_core GTest::gtest_main)
    morserunner_apply_warnings(${name})
    add_test(NAME ${name} COMMAND ${name})
endfunction()

mr_add_dsp_test(test_morse_table)
mr_add_dsp_test(test_blackman_harris)
mr_add_dsp_test(test_morse_keyer)
mr_add_dsp_test(test_moving_average)
mr_add_dsp_test(test_ping_pong_filter)
mr_add_dsp_test(test_modulator)
mr_add_dsp_test(test_agc)
mr_add_dsp_test(test_quick_average)
mr_add_dsp_test(test_qsb)
