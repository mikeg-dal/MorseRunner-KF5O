# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

function(mr_add_audio_test name)
    add_executable(${name} ${name}.cpp)
    target_link_libraries(${name} PRIVATE
        mr_audio mr_core mr_third_party::readerwriterqueue GTest::gtest_main)
    morserunner_apply_warnings(${name})
    add_test(NAME ${name} COMMAND ${name})
endfunction()

mr_add_audio_test(test_audio_ring)
