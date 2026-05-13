// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pair of MovingAverage filters that swap roles every N blocks. The
// "active" filter processes audio; the "idle" filter is reset and warms
// up across the next N blocks before swapping in. Without this, the
// long delay line would need to be Reset periodically (to defend against
// numerical drift from the recursive sum), which would inject an audible
// click. With the ping-pong, the reset happens on a filter whose output
// is currently being discarded.
//
// Cadence is kFilterSwapBlocks (10) and lives in Constants.h.

#pragma once

#include "dsp/ComplexBuf.h"
#include "dsp/MovingAverage.h"

#include <cstdint>

namespace mr::dsp {

class PingPongFilter {
public:
    void configure(int points, int passes, int samplesInInput, float gainDb);

    // Filters `buf` in place. Increments the internal block counter; on
    // every kFilterSwapBlocks-th call, swaps the active/idle filters
    // after producing the block (so this block's output is still from
    // the well-warmed filter).
    void process(ComplexBuf& buf);

    // Block index of the next process() call; useful for tests.
    [[nodiscard]] std::uint64_t blockCount() const noexcept { return blockCount_; }

    // Force-reset both filters' state. Called by the Contest engine on
    // run-mode transitions.
    void reset();

private:
    MovingAverage filterA_;
    MovingAverage filterB_;
    // Scratch buffer for warming the idle filter without allocating
    // every block. Sized once at configure() to samplesInInput_.
    ComplexBuf scratch_;
    bool aIsActive_ = true;
    std::uint64_t blockCount_ = 0;
};

}  // namespace mr::dsp
