# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.28)

project(MorseRunner
    VERSION 1.68.0
    DESCRIPTION "Amateur-radio CW contest simulator — macOS native"
    HOMEPAGE_URL "http://www.dxatlas.com/MorseRunner/"
    LANGUAGES CXX OBJC OBJCXX)

# ── Platform guard ──────────────────────────────────────────────────────────
# This port targets macOS exclusively. The signing / notarization /
# Core-Audio integration is too platform-specific to abstract; trying to
# build elsewhere would silently produce a broken artifact.
if(NOT APPLE)
    message(FATAL_ERROR "This port targets macOS only; cross-platform support is not a goal.")
endif()

# ── C++ standard ────────────────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── macOS deployment ────────────────────────────────────────────────────────
# Apple Silicon only. Rosetta is explicitly out of scope; Intel Macs are
# end-of-life for new audio-app development as of 2026.
# Qt 6.10's official installer ships frameworks built for macOS 13.0;
# we cannot reasonably target below the Qt floor because the dylibs would
# refuse to load. If you switch to a Qt build with a lower minimum (e.g.
# Homebrew's qt @ 6.7 still targets 12.0), drop this back to 12.0.
if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "macOS deployment target" FORCE)
endif()
if(NOT DEFINED CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architectures" FORCE)
endif()

# ── Local CMake modules ─────────────────────────────────────────────────────
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(CompileWarnings)
include(MacOSBundle)
include(CodeSigning)
include(Notarization)
include(ThirdParty)

# ── Qt 6 ────────────────────────────────────────────────────────────────────
# Multimedia is required for QAudioSink (audio output). Network is required
# for the Help → Web Page menu items (QDesktopServices is in Gui, but we
# leave Network listed in case future scoreboard work needs it; pruned now).
find_package(Qt6 6.10 REQUIRED COMPONENTS Core Gui Widgets Multimedia)
qt_standard_project_setup()

# Build options
option(MORSERUNNER_BUILD_TESTS "Build unit and golden-WAV tests" ON)
option(MORSERUNNER_ENABLE_TSAN "Build with ThreadSanitizer (Debug only)" OFF)
option(MORSERUNNER_ENABLE_ASAN "Build with AddressSanitizer (Debug only)" OFF)
option(MORSERUNNER_BUILD_GOLDEN "Build the reference-data dump tools for the Swift port" OFF)

if(MORSERUNNER_ENABLE_TSAN)
    add_compile_options(-fsanitize=thread -fno-omit-frame-pointer)
    add_link_options(-fsanitize=thread)
endif()
if(MORSERUNNER_ENABLE_ASAN)
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()

# ── Sub-targets ─────────────────────────────────────────────────────────────
add_subdirectory(src)
add_subdirectory(resources)
if(MORSERUNNER_BUILD_GOLDEN)
    add_subdirectory(tools/golden)
endif()

if(MORSERUNNER_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# ── App bundle ──────────────────────────────────────────────────────────────
# The bundle target itself is small; all real code lives in module libraries
# under src/. main.cpp is the only translation unit that gets linked into
# the bundle directly.
qt_add_executable(MorseRunner MACOSX_BUNDLE
    src/app/main.cpp
)

target_link_libraries(MorseRunner PRIVATE
    mr_app           # AppController, glue
    mr_ui            # MainWindow + widgets
    mr_audio         # AudioEngine, ring buffer, WAV writer
    mr_simulation    # Contest, Station, DxOperator
    mr_scoring       # QsoLog, ExtractPrefix, ScoreWpx/Hst, Crc32
    mr_persistence   # Settings + migration
    mr_dsp           # MorseKeyer, filters, modulator, AGC
    mr_core          # Constants, Theme, Random, Logging
    mr_util          # PlatformPaths, UrlOpener
)

morserunner_apply_warnings(MorseRunner)
morserunner_configure_bundle(MorseRunner)
morserunner_sign(MorseRunner)   # opt-in via MR_SIGN_IDENTITY; no-op if unset
