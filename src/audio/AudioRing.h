// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Wraps moodycamel::ReaderWriterQueue<AudioFrame> as the single SPSC
// hand-off between the SimulationWorker (producer) and AudioEngine
// (consumer). The wrapper isolates the third-party type so the rest of
// the codebase never includes its header directly — making it easy to
// swap implementations later if needed.

#pragma once

#include "audio/AudioFrame.h"
#include "core/Constants.h"

#include <readerwriterqueue.h>

#include <cstddef>

namespace mr::audio {

using AudioRing = moodycamel::ReaderWriterQueue<AudioFrame>;

[[nodiscard]] inline AudioRing makeAudioRing() {
    // Pre-size to kAudioRingFrames so the underlying ring never has to
    // grow at runtime — growth would allocate, defeating the SPSC
    // guarantee.
    return AudioRing(static_cast<std::size_t>(mr::constants::Audio::kAudioRingFrames));
}

}  // namespace mr::audio
