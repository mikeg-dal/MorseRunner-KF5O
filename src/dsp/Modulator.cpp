// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/Modulator.h"

#include "core/Constants.h"
#include "core/DelphiRound.h"

#include <cmath>

namespace mr::dsp {

Modulator::Modulator(int sampleRate, float carrierFreqHz)
    : sampleRate_(sampleRate), carrierFreq_(carrierFreqHz) {
    rebuildTable();
}

void Modulator::setSampleRate(int sampleRate) {
    if (sampleRate <= 0 || sampleRate == sampleRate_) {
        return;
    }
    sampleRate_ = sampleRate;
    rebuildTable();
    sampleIndex_ = 0;
}

void Modulator::setCarrierFreq(float hz) {
    if (hz <= 0.0F || hz == carrierFreq_) {
        return;
    }
    carrierFreq_ = hz;
    rebuildTable();
    sampleIndex_ = 0;
}

void Modulator::rebuildTable() {
    using mr::constants::Math::kTwoPi;
    // Pascal: TModulator.CalcSinCos rounds SR/Freq to the nearest integer
    // and then back-computes the *actual* carrier frequency from that —
    // so the table fits an integer number of periods exactly. We adopt
    // the same trick (and update carrierFreq_ to the rounded value) so
    // the table never needs wrap-around interpolation.
    const int cnt = std::max(2, mr::core::delphiRound(static_cast<double>(sampleRate_) / static_cast<double>(carrierFreq_)));
    carrierFreq_ = static_cast<float>(sampleRate_) / static_cast<float>(cnt);

    sn_.assign(static_cast<std::size_t>(cnt), 0.0F);
    cs_.assign(static_cast<std::size_t>(cnt), 0.0F);

    const double dPhi = kTwoPi / static_cast<double>(cnt);
    sn_[0] = 0.0F;
    cs_[0] = 1.0F;
    if (cnt > 1) {
        sn_[1] = static_cast<float>(std::sin(dPhi));
        cs_[1] = static_cast<float>(std::cos(dPhi));
    }
    // Numerically stable iteration: complex multiplication by exp(j·dPhi).
    for (std::size_t i = 2; i < sn_.size(); ++i) {
        cs_[i] = cs_[1] * cs_[i - 1] - sn_[1] * sn_[i - 1];
        sn_[i] = cs_[1] * sn_[i - 1] + sn_[1] * cs_[i - 1];
    }
}

void Modulator::modulate(const ComplexBuf& in, std::span<float> out) {
    // Pascal: Result[i] := Data.Re[i] * Sn[FSampleNo] - Data.Im[i] * Cs[FSampleNo].
    const int tableSize = static_cast<int>(sn_.size());
    const std::size_t n = std::min(in.re.size(), out.size());
    int idx = sampleIndex_;
    for (std::size_t i = 0; i < n; ++i) {
        out[i] = in.re[i] * sn_[static_cast<std::size_t>(idx)]
                 - in.im[i] * cs_[static_cast<std::size_t>(idx)];
        idx = (idx + 1) % tableSize;
    }
    sampleIndex_ = idx;
}

}  // namespace mr::dsp
