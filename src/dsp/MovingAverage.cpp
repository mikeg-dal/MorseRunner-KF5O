// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/MovingAverage.h"

#include <algorithm>
#include <cmath>

namespace mr::dsp {

MovingAverage::MovingAverage() {
    reset();
    recomputeNorm();
}

void MovingAverage::configure(int points, int passes, int samplesInInput, float gainDb) {
    if (points > 0) {
        points_ = points;
    }
    if (passes > 0) {
        passes_ = passes;
    }
    if (samplesInInput > 0) {
        samplesInInput_ = samplesInInput;
    }
    gainDb_ = gainDb;
    reset();
    recomputeNorm();
}

void MovingAverage::setSamplesInInput(int samplesInInput) {
    if (samplesInInput <= 0 || samplesInInput == samplesInInput_) {
        return;
    }
    samplesInInput_ = samplesInInput;
    reset();
}

void MovingAverage::setPoints(int points) {
    if (points <= 0 || points == points_) {
        return;
    }
    points_ = points;
    reset();
    recomputeNorm();
}

void MovingAverage::setPasses(int passes) {
    if (passes <= 0 || passes == passes_) {
        return;
    }
    passes_ = passes;
    reset();
    recomputeNorm();
}

void MovingAverage::setGainDb(float gainDb) {
    if (gainDb == gainDb_) {
        return;
    }
    gainDb_ = gainDb;
    recomputeNorm();
}

void MovingAverage::recomputeNorm() {
    // Pascal: FNorm := Power(10, 0.05*FGainDb) * IntPower(FPoints, -FPasses).
    // The power-of-Points term compensates for the cascade gain
    // (each pass multiplies by Points); the dB term applies the user's
    // requested gain on top.
    const double linearGain = std::pow(10.0, 0.05 * static_cast<double>(gainDb_));
    const double normalize = std::pow(static_cast<double>(points_), -passes_);
    norm_ = static_cast<float>(linearGain * normalize);
}

void MovingAverage::resetBuffer(std::vector<std::vector<float>>& bufChain) const {
    bufChain.assign(static_cast<std::size_t>(passes_ + 1),
                    std::vector<float>(
                        static_cast<std::size_t>(samplesInInput_ + points_), 0.0F));
}

void MovingAverage::reset() {
    resetBuffer(bufRe_);
    resetBuffer(bufIm_);
}

void MovingAverage::doFilter(std::span<const float> in, std::span<float> out,
                             std::vector<std::vector<float>>& bufChain) {
    const std::size_t inLen = in.size();
    const std::size_t bufLen = static_cast<std::size_t>(samplesInInput_ + points_);

    // PushArray(in, bufChain[0]): shift bufChain[0] left by inLen and
    // append the new input at the right. The buffer is sized so this
    // never overflows when in.size() == samplesInInput_; we guard for
    // mismatched callers anyway.
    {
        auto& dst = bufChain[0];
        if (inLen >= dst.size()) {
            // Input alone fills (or overflows) the buffer — copy the
            // tail of `in` directly. Degenerate path; never taken in
            // production where inLen == samplesInInput_.
            std::copy(in.end() - static_cast<std::ptrdiff_t>(dst.size()),
                      in.end(), dst.begin());
        } else {
            const std::size_t keep = dst.size() - inLen;
            std::move(dst.begin() + static_cast<std::ptrdiff_t>(inLen), dst.end(), dst.begin());
            std::copy(in.begin(), in.end(), dst.begin() + static_cast<std::ptrdiff_t>(keep));
        }
    }

    // Multi-pass. Each pass shifts its destination buffer left by
    // samplesInInput, preserving the last `points` samples as the new
    // left edge, then runs the recursive moving-sum y[i] = y[i-1] -
    // x[i-Points] + x[i] starting at i = Points.
    for (int p = 1; p <= passes_; ++p) {
        auto& dst = bufChain[static_cast<std::size_t>(p)];
        const auto& src = bufChain[static_cast<std::size_t>(p - 1)];
        const std::size_t shift = static_cast<std::size_t>(samplesInInput_);
        if (shift < dst.size()) {
            std::move(dst.begin() + static_cast<std::ptrdiff_t>(shift), dst.end(),
                      dst.begin());
        }
        const std::size_t startIdx = static_cast<std::size_t>(points_);
        for (std::size_t i = startIdx; i < bufLen; ++i) {
            dst[i] = dst[i - 1] - src[i - startIdx] + src[i];
        }
    }

    // GetResult: take samplesInInput_ samples starting at index points_,
    // multiply by the cached normalization factor.
    const auto& finalBuf = bufChain[static_cast<std::size_t>(passes_)];
    const std::size_t outLen = std::min(out.size(), static_cast<std::size_t>(samplesInInput_));
    for (std::size_t i = 0; i < outLen; ++i) {
        out[i] = finalBuf[static_cast<std::size_t>(points_) + i] * norm_;
    }
}

void MovingAverage::process(std::span<const float> in, std::span<float> out) {
    doFilter(in, out, bufRe_);
}

void MovingAverage::processComplex(ComplexBuf& buf) {
    doFilter(buf.re, buf.re, bufRe_);
    doFilter(buf.im, buf.im, bufIm_);
}

}  // namespace mr::dsp
