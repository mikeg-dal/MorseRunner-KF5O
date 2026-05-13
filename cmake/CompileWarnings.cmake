# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# morserunner_apply_warnings(<target>)
#
# Applies the project's standard compiler-warning posture. Clang on Apple
# Silicon is the only supported compiler; we lean on its diagnostics rather
# than chasing GCC-portable flag sets.
function(morserunner_apply_warnings target)
    target_compile_options(${target} PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        -Wshadow
        -Wnon-virtual-dtor
        -Wcast-align
        -Wunused
        -Woverloaded-virtual
        -Wconversion
        -Wsign-conversion
        -Wnull-dereference
        -Wdouble-promotion
        -Wformat=2
        # Warnings-as-errors stay off in v1 to keep the build green while
        # Qt 6 deprecates and re-shapes APIs across point releases.
    )
endfunction()
