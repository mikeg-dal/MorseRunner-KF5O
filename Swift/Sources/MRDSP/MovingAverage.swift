// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/MovingAverage.cpp (VCL/MovAvg.pas). Multi-pass
// cumulative-sum moving average. Each pass uses the recursion
//
//     y[i] = y[i-1] - x[i - Points] + x[i]
//
// which is O(1) per sample regardless of Points. P passes through it
// approximate a Gaussian.
//
// State (delay line) persists across calls — necessary so successive
// blocks join without a click at the boundary. `reset()` zeroes the
// state; the PingPongFilter calls it on the *idle* filter every
// filterSwapBlocks blocks.
//
// Storage: the C++ keeps `passes + 1` rows of `samplesInInput + points`
// floats per channel; here each channel is one flat array of those rows
// (row p at offset p * rowLen). Same arithmetic, same order.

import Darwin

/// Internal building block (used by PingPongFilter).
final class MovingAverage {
    private(set) var points = 129
    private(set) var passes = 3
    private(set) var samplesInInput = 512
    private(set) var gainDb: Float = 0.0
    private var norm: Float = 1.0

    // Row 0 — input history (PushArray destination); row i — output of
    // the i-th pass.
    private var bufRe: [Float] = []
    private var bufIm: [Float] = []

    private var rowLen: Int { samplesInInput + points }

    init() {
        reset()
        recomputeNorm()
    }

    /// Configures the filter. Resets state. Pascal defaults: points=129,
    /// passes=3, samplesInInput=512, gainDb=0.
    func configure(points: Int, passes: Int, samplesInInput: Int, gainDb: Float) {
        if points > 0 {
            self.points = points
        }
        if passes > 0 {
            self.passes = passes
        }
        if samplesInInput > 0 {
            self.samplesInInput = samplesInInput
        }
        self.gainDb = gainDb
        reset()
        recomputeNorm()
    }

    func setSamplesInInput(_ samplesInInput: Int) {
        if samplesInInput <= 0 || samplesInInput == self.samplesInInput {
            return
        }
        self.samplesInInput = samplesInInput
        reset()
    }

    func setPoints(_ points: Int) {
        if points <= 0 || points == self.points {
            return
        }
        self.points = points
        reset()
        recomputeNorm()
    }

    func setPasses(_ passes: Int) {
        if passes <= 0 || passes == self.passes {
            return
        }
        self.passes = passes
        reset()
        recomputeNorm()
    }

    func setGainDb(_ gainDb: Float) {
        if gainDb == self.gainDb {
            return
        }
        self.gainDb = gainDb
        recomputeNorm()
    }

    private func recomputeNorm() {
        // Pascal: FNorm := Power(10, 0.05*FGainDb) * IntPower(FPoints, -FPasses).
        let linearGain = pow(10.0, 0.05 * Double(gainDb))
        let normalize = pow(Double(points), Double(-passes))
        norm = Float(linearGain * normalize)
    }

    /// Zeroes all delay lines.
    func reset() {
        let n = (passes + 1) * rowLen
        bufRe = [Float](repeating: 0, count: n)
        bufIm = [Float](repeating: 0, count: n)
    }

    /// Filters `input` into `output` (first min(output.count,
    /// samplesInInput) samples written). Use `process(_:)` for in-place.
    func process(_ input: [Float], _ output: inout [Float]) {
        input.withUnsafeBufferPointer { i in
            output.withUnsafeMutableBufferPointer { o in
                doFilter(i, o, &bufRe)
            }
        }
    }

    /// In-place form of `process(_:_:)` (C++ `process(x, x)`).
    func process(_ data: inout [Float]) {
        data.withUnsafeMutableBufferPointer { o in
            doFilter(UnsafeBufferPointer(o), o, &bufRe)
        }
    }

    /// Pointer form for callers that filter a sub-range of a larger buffer.
    func process(_ input: UnsafeBufferPointer<Float>, _ output: UnsafeMutableBufferPointer<Float>) {
        doFilter(input, output, &bufRe)
    }

    /// Filters a ComplexBuf in place (a private second delay chain for
    /// the Im channel so Re/Im don't cross-contaminate).
    func processComplex(_ buf: inout ComplexBuf) {
        buf.re.withUnsafeMutableBufferPointer { o in
            doFilter(UnsafeBufferPointer(o), o, &bufRe)
        }
        buf.im.withUnsafeMutableBufferPointer { o in
            doFilter(UnsafeBufferPointer(o), o, &bufIm)
        }
    }

    // The whole input is pushed into row 0 before any output is written,
    // so `input` and `output` may alias (the C++ in-place use).
    private func doFilter(_ input: UnsafeBufferPointer<Float>,
                          _ output: UnsafeMutableBufferPointer<Float>,
                          _ chain: inout [Float]) {
        let inLen = input.count
        let bufLen = rowLen
        let points = self.points
        let passes = self.passes
        let shift = samplesInInput
        let norm = self.norm

        chain.withUnsafeMutableBufferPointer { c in
            let base = c.baseAddress!
            // PushArray(in, row 0): shift row 0 left by inLen and append
            // the new input at the right.
            do {
                let dst = base
                if inLen >= bufLen {
                    // Input alone fills (or overflows) the buffer — copy
                    // the tail of `in` directly. Degenerate path.
                    let from = inLen - bufLen
                    for k in 0..<bufLen {
                        dst[k] = input[from + k]
                    }
                } else {
                    let keep = bufLen - inLen
                    for k in 0..<keep {
                        dst[k] = dst[inLen + k]
                    }
                    for k in 0..<inLen {
                        dst[keep + k] = input[k]
                    }
                }
            }

            // Multi-pass. Each pass shifts its destination row left by
            // samplesInInput, preserving the last `points` samples as the
            // new left edge, then runs the recursive moving-sum starting
            // at i = Points.
            if passes >= 1 {
                for p in 1...passes {
                    let dst = base + p * bufLen
                    let src = base + (p - 1) * bufLen
                    if shift < bufLen {
                        for k in 0..<(bufLen - shift) {
                            dst[k] = dst[shift + k]
                        }
                    }
                    var i = points
                    while i < bufLen {
                        dst[i] = dst[i - 1] - src[i - points] + src[i]
                        i += 1
                    }
                }
            }

            // GetResult: take samplesInInput samples starting at index
            // points, multiply by the cached normalization factor.
            let finalRow = base + passes * bufLen
            let outLen = min(output.count, samplesInInput)
            for i in 0..<outLen {
                output[i] = finalRow[points + i] * norm
            }
        }
    }
}
