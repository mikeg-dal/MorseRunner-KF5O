// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/PingPongFilter.h"

#include "core/Constants.h"

namespace mr::dsp {

void PingPongFilter::configure(int points, int passes, int samplesInInput, float gainDb) {
    filterA_.configure(points, passes, samplesInInput, gainDb);
    filterB_.configure(points, passes, samplesInInput, gainDb);
    scratch_.resize(static_cast<std::size_t>(samplesInInput));
    aIsActive_ = true;
    blockCount_ = 0;
}

void PingPongFilter::reset() {
    filterA_.reset();
    filterB_.reset();
    aIsActive_ = true;
    blockCount_ = 0;
}

void PingPongFilter::process(ComplexBuf& buf) {
    using mr::constants::Audio::kFilterSwapBlocks;

    // Pascal: Contest.pas::GetAudio runs Filt2 first (in-place), then
    // Filt (returning a new array). Every 10 blocks SwapFilters is
    // called, which swaps the references and Reset's the now-idle one.
    //
    // Our model is simpler: a single "active" filter shapes this block,
    // the "idle" filter receives the same input but its output is
    // discarded — its purpose is to be warmed up so that, when promoted,
    // it joins seamlessly. Same audible behavior, fewer moving parts.
    MovingAverage& active = aIsActive_ ? filterA_ : filterB_;
    MovingAverage& idle = aIsActive_ ? filterB_ : filterA_;

    // Warm the idle filter with the same input (output discarded).
    // scratch_ is pre-sized in configure(); we just reload its contents.
    if (scratch_.size() < buf.size()) {
        scratch_.resize(buf.size());
    }
    std::copy(buf.re.begin(), buf.re.end(), scratch_.re.begin());
    std::copy(buf.im.begin(), buf.im.end(), scratch_.im.begin());
    idle.processComplex(scratch_);

    // Produce the audible output from the active filter (in place).
    active.processComplex(buf);

    ++blockCount_;
    if (blockCount_ % kFilterSwapBlocks == 0) {
        // Promote the idle filter; reset the formerly-active one so it
        // gets a fresh delay line for the next 10-block window.
        active.reset();
        aIsActive_ = !aIsActive_;
    }
}

}  // namespace mr::dsp
