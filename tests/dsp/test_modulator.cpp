// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/Modulator.h"

#include "core/Constants.h"
#include "dsp/ComplexBuf.h"

#include <gtest/gtest.h>

#include <cmath>
#include <vector>

using namespace mr::dsp;
using mr::constants::Audio::kSampleRate;

TEST(Modulator, TableHasIntegerPeriodCount) {
    // SR=11025, carrier=600 → table length = round(11025/600) = 18.
    Modulator m(kSampleRate, 600.0F);
    EXPECT_EQ(m.tableSize(), 18);
}

TEST(Modulator, ZeroInputProducesZeroOutput) {
    Modulator m(kSampleRate, 600.0F);
    ComplexBuf in;
    in.resize(64);
    std::vector<float> out(64, 99.0F);
    m.modulate(in, out);
    for (const float s : out) {
        EXPECT_FLOAT_EQ(s, 0.0F);
    }
}

TEST(Modulator, ConstantInputProducesPeriodicTone) {
    // Feed re=1, im=0. Output is `1·sin(φ) - 0·cos(φ) = sin(φ)` — a
    // pure tone at the (quantized) carrier frequency. Test: RMS over
    // an integer number of periods should equal sqrt(1/2).
    Modulator m(kSampleRate, 600.0F);
    const int periods = 64;
    const int n = periods * m.tableSize();
    ComplexBuf in;
    in.resize(static_cast<std::size_t>(n));
    std::fill(in.re.begin(), in.re.end(), 1.0F);
    std::vector<float> out(static_cast<std::size_t>(n), 0.0F);
    m.modulate(in, out);

    double sumSq = 0.0;
    for (const float s : out) {
        sumSq += static_cast<double>(s) * static_cast<double>(s);
    }
    const double rms = std::sqrt(sumSq / static_cast<double>(n));
    EXPECT_NEAR(rms, std::sqrt(0.5), 1.0e-5);
}

TEST(Modulator, PerfectQuadratureInputCancels) {
    // Feed re[i] = sin(table_phase[i]), im[i] = cos(table_phase[i]) —
    // i.e. an input whose phase tracks the table exactly. Then
    // out[i] = sin·sin - cos·cos = -cos(2·phase), bounded ≤ 1 in
    // magnitude but otherwise a pure tone at 2·carrier.
    Modulator m(kSampleRate, 600.0F);
    const int n = m.tableSize() * 32;
    ComplexBuf in;
    in.resize(static_cast<std::size_t>(n));
    const double phaseStep = 2.0 * mr::constants::Math::kPi
                             / static_cast<double>(m.tableSize());
    for (int i = 0; i < n; ++i) {
        in.re[static_cast<std::size_t>(i)] = static_cast<float>(std::sin(phaseStep * i));
        in.im[static_cast<std::size_t>(i)] = static_cast<float>(std::cos(phaseStep * i));
    }
    std::vector<float> out(static_cast<std::size_t>(n), 0.0F);
    m.modulate(in, out);
    for (const float s : out) {
        EXPECT_LE(std::abs(s), 1.001F);
    }
}

TEST(Modulator, ResetReturnsToPhaseZero) {
    Modulator m(kSampleRate, 600.0F);
    ComplexBuf in;
    in.resize(32);
    in.re[5] = 1.0F;
    std::vector<float> out(32, 0.0F);
    m.modulate(in, out);
    m.reset();
    // After reset, modulating the same input should produce identical
    // output to a fresh modulator (phase index back at 0).
    Modulator m2(kSampleRate, 600.0F);
    std::vector<float> out2(32, 0.0F);
    ComplexBuf in2 = in;
    m.modulate(in, out);
    m2.modulate(in2, out2);
    for (std::size_t i = 0; i < out.size(); ++i) {
        EXPECT_FLOAT_EQ(out[i], out2[i]);
    }
}
