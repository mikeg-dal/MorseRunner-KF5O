# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Third-party dependencies fetched via FetchContent so the build is fully
# self-contained. We keep this list intentionally short — every entry is a
# liability to audit and re-sign.

include(FetchContent)
set(FETCHCONTENT_QUIET FALSE)

# moodycamel::ReaderWriterQueue — header-only single-producer
# single-consumer lock-free queue. Used as the audio-engine ring between
# SimulationWorker (sim thread, producer) and AudioEngine (audio thread,
# consumer). License: BSD 2-clause / Boost (header dual-licensed).
FetchContent_Declare(readerwriterqueue
    GIT_REPOSITORY https://github.com/cameron314/readerwriterqueue.git
    GIT_TAG v1.0.6
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(readerwriterqueue)

# The upstream package exports a target `readerwriterqueue` already (it is
# an INTERFACE target with the include directory set). Alias it under our
# `mr_third_party::` namespace so consuming code is explicit about the
# external boundary.
if(NOT TARGET mr_third_party::readerwriterqueue)
    add_library(mr_third_party::readerwriterqueue ALIAS readerwriterqueue)
endif()
