// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/QuickAverage.cpp (VCL/QuickAvg.pas, TQuickAverage).
// One-sample-at-a-time recursive multi-pass moving average. Different
// from MovingAverage in that the delay line is circular and the
// bookkeeping is per-sample instead of per-block — used by Qsb where new
// gain samples are generated one at a time to drive Rayleigh fading.
//
// Storage: `passes + 1` rows of `points` doubles per channel, flattened
// (row p at offset p * points).

import Darwin

/// Internal building block (used by Qsb).
final class QuickAverage {
    private(set) var points = 128
    private(set) var passes = 4
    private var idx = 0
    private var prevIdx = 127
    private var scale: Float = 1.0
    // Bufs are doubles in the original — accumulated state needs the
    // extra headroom because the cumulative sums can grow unbounded.
    private var reBufs: [Double] = []
    private var imBufs: [Double] = []

    init() {
        reset()
    }

    func setPoints(_ points: Int) {
        self.points = max(1, points)
        reset()
    }

    func setPasses(_ passes: Int) {
        // Pascal: clamps to [1, 8]; the recursion's numerical stability
        // degrades past 8 passes.
        self.passes = min(max(passes, 1), 8)
        reset()
    }

    func reset() {
        let n = (passes + 1) * points
        reBufs = [Double](repeating: 0, count: n)
        imBufs = [Double](repeating: 0, count: n)
        scale = Float(pow(Double(points), Double(-passes)))
        idx = 0
        prevIdx = points - 1
    }

    private func doFilter(_ v: Float, _ bufs: inout [Double]) -> Float {
        let points = self.points
        let passes = self.passes
        let idx = self.idx
        let prevIdx = self.prevIdx
        return bufs.withUnsafeMutableBufferPointer { b in
            var result = Double(v)
            for p in 1...passes {
                let prev = b[p * points + prevIdx]
                let curr = b[(p - 1) * points + idx]
                b[(p - 1) * points + idx] = result
                result = prev - curr + result
            }
            b[passes * points + idx] = result
            return Float(result) * scale
        }
    }

    /// Real-valued one-shot filter call. Returns the filtered output for
    /// the just-pushed sample.
    func filter(_ v: Float) -> Float {
        let out = doFilter(v, &reBufs)
        prevIdx = idx
        idx = (idx + 1) % points
        return out
    }

    /// Complex-valued one-shot filter call (C++ out-params → tuple).
    func filterComplex(_ re: Float, _ im: Float) -> (re: Float, im: Float) {
        let outRe = doFilter(re, &reBufs)
        let outIm = doFilter(im, &imBufs)
        prevIdx = idx
        idx = (idx + 1) % points
        return (outRe, outIm)
    }

    /// Magnitude of the filtered (re, im) pair.
    func filteredModule(_ re: Float, _ im: Float) -> Float {
        let (r, i) = filterComplex(re, im)
        return (r * r + i * i).squareRoot()
    }
}
