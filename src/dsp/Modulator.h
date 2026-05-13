// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/Mixers.pas's TModulator. Converts a complex (I/Q) signal
// to a real PCM stream by multiplying with a precomputed sin/cos table:
//
//     out[i] = re[i] · sin(phi[i]) - im[i] · cos(phi[i])
//
// Phase advances one slot per sample through a table of length
// round(SR / carrierFreq), so an integer number of periods fits and we
// never need to wrap a floating-point phase. The original derives the
// table via complex rotation (Sn[i] = Sn[1]·Cs[i-1] + Cs[1]·Sn[i-1])
// rather than calling Sin/Cos for every element — a numerical-stability
// trick we preserve verbatim.

#pragma once

#include "dsp/ComplexBuf.h"

#include <cstddef>
#include <span>
#include <vector>

namespace mr::dsp {

class Modulator {
public:
    Modulator(int sampleRate, float carrierFreqHz);

    void setSampleRate(int sampleRate);
    void setCarrierFreq(float hz);

    [[nodiscard]] int sampleRate() const noexcept { return sampleRate_; }
    [[nodiscard]] float carrierFreq() const noexcept { return carrierFreq_; }
    [[nodiscard]] int tableSize() const noexcept { return static_cast<int>(sn_.size()); }

    // Modulates a complex (I/Q) buffer to real audio. `out` must be at
    // least as long as `in.size()`; only the first `in.size()` samples
    // are written.
    void modulate(const ComplexBuf& in, std::span<float> out);

    // Resets the phase index. The Contest engine calls this on each
    // run-mode change so the tone starts at a deterministic point.
    void reset() noexcept { sampleIndex_ = 0; }

private:
    void rebuildTable();

    int sampleRate_;
    float carrierFreq_;
    std::vector<float> sn_;
    std::vector<float> cs_;
    int sampleIndex_ = 0;
};

}  // namespace mr::dsp
