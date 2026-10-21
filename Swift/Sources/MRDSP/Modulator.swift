// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/Modulator.cpp (VCL/Mixers.pas's TModulator). Converts a
// complex (I/Q) signal to a real PCM stream by multiplying with a
// precomputed sin/cos table:
//
//     out[i] = re[i] · sin(phi[i]) - im[i] · cos(phi[i])
//
// Phase advances one slot per sample through a table of length
// round(SR / carrierFreq), so an integer number of periods fits and we
// never need to wrap a floating-point phase. The original derives the
// table via complex rotation (Sn[i] = Sn[1]·Cs[i-1] + Cs[1]·Sn[i-1])
// rather than calling Sin/Cos for every element — a numerical-stability
// trick we preserve verbatim.

import MRCore

public final class Modulator {
    public private(set) var sampleRate: Int
    public private(set) var carrierFreq: Float
    private var sn: [Float] = []
    private var cs: [Float] = []
    private var sampleIndex = 0

    public var tableSize: Int { sn.count }

    /// - Precondition: `sampleRate > 0` and `carrierFreq > 0` (the table
    ///   length is round(sampleRate / carrierFreq)); the setters ignore
    ///   such values instead.
    public init(sampleRate: Int, carrierFreq: Float) {
        precondition(sampleRate > 0, "Modulator: sampleRate must be positive")
        precondition(carrierFreq > 0, "Modulator: carrierFreq must be positive")
        self.sampleRate = sampleRate
        self.carrierFreq = carrierFreq
        rebuildTable()
    }

    public func setSampleRate(_ sampleRate: Int) {
        if sampleRate <= 0 || sampleRate == self.sampleRate {
            return
        }
        self.sampleRate = sampleRate
        rebuildTable()
        sampleIndex = 0
    }

    /// Ignores values that are not positive (NaN included: the C++
    /// `hz <= 0` test lets NaN through into an undefined conversion).
    public func setCarrierFreq(_ hz: Float) {
        if !(hz > 0.0) || hz == carrierFreq {
            return
        }
        carrierFreq = hz
        rebuildTable()
        sampleIndex = 0
    }

    /// Resets the phase index. The Contest engine calls this on each
    /// run-mode change so the tone starts at a deterministic point.
    public func reset() {
        sampleIndex = 0
    }

    private func rebuildTable() {
        // Pascal: TModulator.CalcSinCos rounds SR/Freq to the nearest
        // integer and then back-computes the *actual* carrier frequency
        // from that — so the table fits an integer number of periods
        // exactly. carrierFreq is updated to the rounded value.
        let cnt = max(2, delphiRound(Double(sampleRate) / Double(carrierFreq)))
        carrierFreq = Float(sampleRate) / Float(cnt)

        sn = [Float](repeating: 0, count: cnt)
        cs = [Float](repeating: 0, count: cnt)

        let dPhi = MathK.twoPi / Double(cnt)
        sn[0] = 0.0
        cs[0] = 1.0
        if cnt > 1 {
            // C++ std::sin(dPhi)/std::cos(dPhi) pair → one sincos call.
            let sc = sinCos(dPhi)
            sn[1] = Float(sc.sin)
            cs[1] = Float(sc.cos)
        }
        // Numerically stable iteration: complex multiplication by exp(j·dPhi).
        var i = 2
        while i < cnt {
            cs[i] = cs[1] * cs[i - 1] - sn[1] * sn[i - 1]
            sn[i] = cs[1] * sn[i - 1] + sn[1] * cs[i - 1]
            i += 1
        }
    }

    /// Modulates a complex (I/Q) buffer to real audio. Writes the first
    /// min(input.size, out.count) samples of `out`.
    ///
    /// - Precondition: `input.re.count == input.im.count`.
    public func modulate(_ input: ComplexBuf, _ out: UnsafeMutableBufferPointer<Float>) {
        // Pascal: Result[i] := Data.Re[i] * Sn[FSampleNo] - Data.Im[i] * Cs[FSampleNo].
        precondition(input.isConsistent, "Modulator.modulate: re and im lengths differ")
        let tableSize = sn.count
        let n = min(input.re.count, out.count)
        var idx = sampleIndex
        sn.withUnsafeBufferPointer { sn in
            cs.withUnsafeBufferPointer { cs in
                input.re.withUnsafeBufferPointer { re in
                    input.im.withUnsafeBufferPointer { im in
                        for i in 0..<n {
                            out[i] = re[i] * sn[idx] - im[i] * cs[idx]
                            idx += 1  // (idx + 1) % tableSize; idx < tableSize
                            if idx == tableSize { idx = 0 }
                        }
                    }
                }
            }
        }
        sampleIndex = idx
    }

    public func modulate(_ input: ComplexBuf, _ out: inout [Float]) {
        out.withUnsafeMutableBufferPointer { modulate(input, $0) }
    }
}
