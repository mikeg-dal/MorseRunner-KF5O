// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

#include "core/Constants.h"

#include <array>
#include <cstddef>
#include <cstdint>

namespace mr::audio {

// Single audio block exchanged across the SPSC ring between the
// simulation thread (producer) and the audio thread (consumer).
//
// Trivially copyable so moodycamel::ReaderWriterQueue can shuttle it
// without invoking allocators. We size `samples` once at compile time
// to the maximum allowed buffer (Audio::kMaxBufferSamples = 2048) and
// trust `n` to record how many of those slots are live; the ring's
// fixed slot size is the price we pay for guaranteed-allocation-free
// hand-off.
struct alignas(64) AudioFrame {
    std::array<float, mr::constants::Audio::kMaxBufferSamples> samples{};
    std::uint16_t n = 0;
    std::uint64_t blockIndex = 0;
};

}  // namespace mr::audio
