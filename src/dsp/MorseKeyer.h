// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/MorseKey.pas. Encodes a free-text message into the keyer
// alphabet (./- /~) and renders an amplitude envelope at the configured
// WPM and sample rate.
//
// Timing math (verbatim from the original):
//
//   SamplesInUnit = round(0.1 · SR · 12 / WPM)
//
// One "unit" is a dot length. A dot is one unit on + one unit off, a
// dash is three units on + one unit off, an inter-character space adds
// two extra units of silence, and the '~' end-of-message marker collapses
// the trailing inter-character silence to a single unit (so successive
// messages don't accumulate trailing gap).

#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace mr::dsp {

class MorseKeyer {
public:
    // `sampleRate` is the audio sample rate (typically Audio::kSampleRate).
    // `wpm` is words-per-minute in the PARIS reference (the same scale
    // the user picks in the WPM spinbox).
    MorseKeyer(int sampleRate, int wpm);

    void setWpm(int wpm) noexcept;
    void setSampleRate(int sampleRate);

    // Renders `text` into a float envelope (range [0, 1]). `text` may be
    // plain ASCII; characters that have no Morse mapping are skipped.
    [[nodiscard]] std::vector<float> renderEnvelope(std::string_view text) const;

    // Sample counts for inspection / testing.
    [[nodiscard]] int samplesPerUnit() const noexcept { return samplesPerUnit_; }
    [[nodiscard]] int rampSamples() const noexcept { return rampSamples_; }

private:
    void recomputeTiming();
    void rebuildRamps();

    int sampleRate_;
    int wpm_;
    int samplesPerUnit_ = 0;
    int rampSamples_ = 0;
    std::vector<float> rampOn_;
    std::vector<float> rampOff_;
};

}  // namespace mr::dsp
