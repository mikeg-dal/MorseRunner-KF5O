// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/BlackmanHarris.h"

#include "core/Constants.h"

#include <cmath>
#include <vector>

namespace mr::dsp {

namespace {

[[nodiscard]] double bhKernel(double x) noexcept {
    using namespace mr::constants::Dsp;
    using namespace mr::constants::Math;
    return kBlackmanHarrisA0
           - kBlackmanHarrisA1 * std::cos(kTwoPi * x * 1.0)
           + kBlackmanHarrisA2 * std::cos(kTwoPi * x * 2.0)
           - kBlackmanHarrisA3 * std::cos(kTwoPi * x * 3.0);
}

}  // namespace

std::vector<float> blackmanHarrisStep(int len) {
    // Pascal: VCL/MorseKey.pas::BlackmanHarrisStepResponse — generate the
    // window kernel, integrate it (cumulative sum), normalize the tail
    // value to 1. Computing in double then narrowing to float keeps the
    // tail-normalization error well below float epsilon.
    std::vector<float> out;
    if (len <= 0) {
        return out;
    }
    std::vector<double> acc(static_cast<std::size_t>(len));
    for (std::size_t i = 0; i < acc.size(); ++i) {
        acc[i] = bhKernel(static_cast<double>(i) / static_cast<double>(len));
    }
    for (std::size_t i = 1; i < acc.size(); ++i) {
        acc[i] += acc[i - 1];
    }
    const double tail = acc.back();
    out.reserve(acc.size());
    if (tail == 0.0) {
        // Degenerate (len=1, kernel(0) = a0 - a1 + a2 - a3). Defensive
        // path: return a single sample = 1 so the keyer still produces
        // a valid envelope.
        for (std::size_t i = 0; i < acc.size(); ++i) {
            out.push_back(1.0F);
        }
        return out;
    }
    const double inv = 1.0 / tail;
    for (const double v : acc) {
        out.push_back(static_cast<float>(v * inv));
    }
    // Pin the final sample exactly to 1.0 so downstream "AddOn" stages
    // do not see an off-by-one-ULP discontinuity.
    out.back() = 1.0F;
    return out;
}

}  // namespace mr::dsp
