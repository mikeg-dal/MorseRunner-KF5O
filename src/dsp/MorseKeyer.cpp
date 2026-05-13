// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/MorseKeyer.h"

#include "core/Constants.h"
#include "dsp/BlackmanHarris.h"
#include "dsp/MorseTable.h"

#include <algorithm>
#include <cmath>

namespace mr::dsp {

namespace {

// Pascal: VCL/MorseKey.pas::GetEnvelope counts units before allocating.
// '.': 2 units on+off, '-': 4 units on+off, ' ': 2 units silence,
// '~': 1 unit silence (terminal short-gap).
int countUnits(std::string_view morse) noexcept {
    int n = 0;
    for (const char c : morse) {
        switch (c) {
            case '.': n += 2; break;
            case '-': n += 4; break;
            case ' ': n += 2; break;
            case '~': n += 1; break;
            default: break;
        }
    }
    return n;
}

}  // namespace

MorseKeyer::MorseKeyer(int sampleRate, int wpm) : sampleRate_(sampleRate), wpm_(wpm) {
    recomputeTiming();
    rebuildRamps();
}

void MorseKeyer::setWpm(int wpm) noexcept {
    if (wpm == wpm_ || wpm <= 0) {
        return;
    }
    wpm_ = wpm;
    recomputeTiming();
}

void MorseKeyer::setSampleRate(int sampleRate) {
    if (sampleRate == sampleRate_ || sampleRate <= 0) {
        return;
    }
    sampleRate_ = sampleRate;
    recomputeTiming();
    rebuildRamps();
}

void MorseKeyer::recomputeTiming() {
    using namespace mr::constants::Dsp;
    // SamplesInUnit = round(0.1 · SR · 12 / WPM). For SR = 11025, WPM = 30:
    // SamplesInUnit = round(441) = 441 — matches Delphi byte-for-byte.
    const double samples = static_cast<double>(kMorseUnitSecondsCoef)
                           * static_cast<double>(sampleRate_)
                           * static_cast<double>(kMorseUnitsPerWpmRef)
                           / static_cast<double>(wpm_);
    samplesPerUnit_ = static_cast<int>(std::lround(samples));
}

void MorseKeyer::rebuildRamps() {
    using namespace mr::constants::Dsp;
    // RampLen = round(2.7 · RiseTime · SR). RiseTime = 5 ms → RampLen ≈ 149
    // samples at SR = 11025. Pascal: VCL/MorseKey.pas::MakeRamp.
    const double len = static_cast<double>(kBlackmanHarrisStretch)
                       * static_cast<double>(kRiseTimeSeconds)
                       * static_cast<double>(sampleRate_);
    rampSamples_ = static_cast<int>(std::lround(len));
    rampOn_ = blackmanHarrisStep(rampSamples_);
    rampOff_.assign(rampOn_.size(), 0.0F);
    // Off-ramp is the on-ramp reversed (so the keying envelope is
    // perfectly symmetric — important for spectral cleanliness).
    for (std::size_t i = 0; i < rampOn_.size(); ++i) {
        rampOff_[rampOn_.size() - 1 - i] = rampOn_[i];
    }
}

std::vector<float> MorseKeyer::renderEnvelope(std::string_view text) const {
    // Auto-detect whether the input is already encoded morse
    // (./- /~/space) or free text. If every char is in the morse
    // alphabet, treat it as already encoded; otherwise run it through
    // encodeMessage first.
    if (samplesPerUnit_ <= 0 || rampSamples_ <= 0) {
        return {};
    }

    auto isEncodedChar = [](char c) {
        return c == '.' || c == '-' || c == ' ' || c == '~';
    };
    bool allEncoded = !text.empty();
    for (const char c : text) {
        if (!isEncodedChar(c)) {
            allEncoded = false;
            break;
        }
    }

    std::string morse;
    if (allEncoded) {
        morse.assign(text.begin(), text.end());
    } else {
        morse = encodeMessage(text);
    }
    if (morse.empty()) {
        return {};
    }

    const int totalUnits = countUnits(morse);
    const int unitSamples = samplesPerUnit_;
    const int ramp = rampSamples_;

    // Pascal: VCL/MorseKey.pas — buffer = ceil(needed / bufSize) * bufSize.
    // Our consumer is the SimulationWorker which pulls fixed-size frames
    // already; we return exactly the number of samples needed and let the
    // caller pad. trueLen below is the audio-visible envelope length.
    const int trueLen = totalUnits * unitSamples + ramp;
    if (trueLen <= 0) {
        return {};
    }

    std::vector<float> out;
    out.resize(static_cast<std::size_t>(trueLen), 0.0F);

    auto pos = std::size_t{0};

    auto addRampOn = [&]() {
        // Copy ramp-on into the envelope, then advance `pos` by ramp.
        std::copy(rampOn_.begin(), rampOn_.end(), out.begin() + static_cast<std::ptrdiff_t>(pos));
        pos += rampOn_.size();
    };
    auto addRampOff = [&]() {
        std::copy(rampOff_.begin(), rampOff_.end(),
                  out.begin() + static_cast<std::ptrdiff_t>(pos));
        pos += rampOff_.size();
    };
    auto addOn = [&](int durUnits) {
        // Pascal: `AddOn(Dur)` fills `Dur*SamplesInUnit - RampLen` samples
        // at 1.0. The ramp before/after eats the rest of the duration.
        const int span = durUnits * unitSamples - ramp;
        if (span > 0) {
            const auto end = pos + static_cast<std::size_t>(span);
            std::fill(out.begin() + static_cast<std::ptrdiff_t>(pos),
                      out.begin() + static_cast<std::ptrdiff_t>(end), 1.0F);
            pos = end;
        }
    };
    auto addOff = [&](int durUnits) {
        // Off-state: just advance `pos` past `Dur*SamplesInUnit - RampLen`
        // samples; the buffer is already zero-initialized.
        const int span = durUnits * unitSamples - ramp;
        if (span > 0) {
            pos += static_cast<std::size_t>(span);
        }
    };

    for (const char c : morse) {
        switch (c) {
            case '.':
                addRampOn();
                addOn(1);
                addRampOff();
                addOff(1);
                break;
            case '-':
                addRampOn();
                addOn(3);
                addRampOff();
                addOff(1);
                break;
            case ' ':
                addOff(2);
                break;
            case '~':
                addOff(1);
                break;
            default:
                break;
        }
    }

    return out;
}

}  // namespace mr::dsp
