// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/PingPongFilter.cpp. Pair of MovingAverage filters that
// swap roles every N blocks. The "active" filter processes audio; the
// "idle" filter is reset and warms up across the next N blocks before
// swapping in. Without this, the long delay line would need to be Reset
// periodically (to defend against numerical drift from the recursive
// sum), which would inject an audible click. With the ping-pong, the
// reset happens on a filter whose output is currently being discarded.
//
// Cadence is AudioK.filterSwapBlocks (10).

import MRCore

public final class PingPongFilter {
    private let filterA = MovingAverage()
    private let filterB = MovingAverage()
    // Scratch buffer for warming the idle filter without allocating
    // every block. Sized once at configure() to samplesInInput.
    private var scratch = ComplexBuf()
    private var aIsActive = true
    /// Block index of the next process() call; useful for tests.
    public private(set) var blockCount: UInt64 = 0

    public init() {}

    public func configure(points: Int, passes: Int, samplesInInput: Int, gainDb: Float) {
        filterA.configure(points: points, passes: passes, samplesInInput: samplesInInput, gainDb: gainDb)
        filterB.configure(points: points, passes: passes, samplesInInput: samplesInInput, gainDb: gainDb)
        scratch.resize(samplesInInput)
        aIsActive = true
        blockCount = 0
    }

    /// Force-reset both filters' state. Called by the Contest engine on
    /// run-mode transitions.
    public func reset() {
        filterA.reset()
        filterB.reset()
        aIsActive = true
        blockCount = 0
    }

    /// Filters `buf` in place. Increments the internal block counter; on
    /// every filterSwapBlocks-th call, swaps the active/idle filters
    /// after producing the block (so this block's output is still from
    /// the well-warmed filter).
    ///
    /// - Precondition: `buf.re.count == buf.im.count`.
    public func process(_ buf: inout ComplexBuf) {
        precondition(buf.isConsistent, "PingPongFilter.process: re and im lengths differ")
        // Pascal: Contest.pas::GetAudio runs Filt2 first (in-place), then
        // Filt (returning a new array). Every 10 blocks SwapFilters is
        // called, which swaps the references and Reset's the now-idle one.
        //
        // Our model is simpler: a single "active" filter shapes this
        // block, the "idle" filter receives the same input but its output
        // is discarded — its purpose is to be warmed up so that, when
        // promoted, it joins seamlessly.
        let active = aIsActive ? filterA : filterB
        let idle = aIsActive ? filterB : filterA

        // Warm the idle filter with the same input (output discarded).
        if scratch.size < buf.size {
            scratch.resize(buf.size)
        }
        for i in 0..<buf.re.count { scratch.re[i] = buf.re[i] }
        for i in 0..<buf.im.count { scratch.im[i] = buf.im[i] }
        idle.processComplex(&scratch)

        // Produce the audible output from the active filter (in place).
        active.processComplex(&buf)

        blockCount += 1
        if blockCount % UInt64(AudioK.filterSwapBlocks) == 0 {
            // Promote the idle filter; reset the formerly-active one so
            // it gets a fresh delay line for the next 10-block window.
            active.reset()
            aIsActive = !aIsActive
        }
    }
}
