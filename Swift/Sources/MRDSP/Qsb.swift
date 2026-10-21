// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/Qsb.cpp (Qsb.pas). Per-station Rayleigh-fading model:
// takes two uniform noise streams, low-passes both through a
// QuickAverage configured for the requested fading bandwidth, and uses
// the magnitude of the result as a slowly-varying amplitude multiplier.
// Applied across each station's rendered keying envelope to give the
// audible "QSB" effect.

import Darwin
import MRCore

public final class Qsb {
    private static let subBlockDivisor = 4
    private static let pointsCoef: Float = 0.37

    private let subBlockSize: Int  // Pascal: BufSize div 4 (at least 1)
    public private(set) var bandwidth: Float = 0.1
    private var gain: Float = 1.0
    private let qsbLevel: Float = 1.0
    private let filt = QuickAverage()
    private let rng: Random

    /// `bufSize` mirrors Ini.BufSize — the gain is updated in groups of
    /// `bufSize/4` samples (the original's pacing, kept for parity).
    /// Sizes below 4 use 1-sample groups.
    public init(bufSize: Int, rng: Random) {
        self.rng = rng
        subBlockSize = max(1, bufSize / Self.subBlockDivisor)
        filt.setPasses(3)
        setBandwidth(0.1)
    }

    /// Ignores values that are not positive (NaN included: the C++
    /// `<= 0` test lets NaN through into an undefined conversion).
    public func setBandwidth(_ bandwidthHz: Float) {
        if !(bandwidthHz > 0.0) {
            return
        }
        bandwidth = bandwidthHz
        // Pascal: Filt.Points := Ceil(0.37 * DEFAULTRATE / ((BufSize div 4) * Value)).
        // The bandwidth maps inversely to the filter length: narrower
        // fade = longer averaging window.
        let sr = Double(AudioK.sampleRate)
        let denom = Double(subBlockSize) * Double(bandwidthHz)
        let points = max(1, Int((Double(Self.pointsCoef) * sr / denom).rounded(.up)))
        filt.setPoints(points)
        // Warm up so the first audible block is already at a settled gain.
        for _ in 0...(points * 3) {
            gain = newGain()
        }
    }

    private func newGain() -> Float {
        // Pascal: Filt.Filter(RndUniform, RndUniform) returns a complex
        // result; its magnitude (scaled by √(3·Points)) is a Rayleigh-
        // distributed amplitude. The further scaling by qsbLevel + (1-lvl)
        // mixes between full fading and unity (defaults to qsbLevel=1).
        let u1 = 2.0 * rng.uniform01() - 1.0
        let u2 = 2.0 * rng.uniform01() - 1.0
        let (reOut, imOut) = filt.filterComplex(u1, u2)
        let magSq = reOut * reOut + imOut * imOut
        var g = (magSq * 3.0 * Float(filt.points)).squareRoot()
        g = g * qsbLevel + (1.0 - qsbLevel)
        return g
    }

    /// Multiplies each sample by a Rayleigh-distributed amplitude that
    /// varies smoothly at the configured bandwidth. Samples past the last
    /// whole sub-block are left untouched (as in the original).
    public func applyTo(_ arr: UnsafeMutableBufferPointer<Float>) {
        let blkCnt = arr.count / subBlockSize
        for b in 0..<blkCnt {
            let target = newGain()
            let dG = (target - gain) / Float(subBlockSize)
            let base = b * subBlockSize
            for i in 0..<subBlockSize {
                arr[base + i] *= gain
                gain += dG
            }
        }
    }

    public func applyTo(_ arr: inout [Float]) {
        arr.withUnsafeMutableBufferPointer { applyTo($0) }
    }
}
