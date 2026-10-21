// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/BlackmanHarris.cpp (VCL/MorseKey.pas's
// `BlackmanHarrisStepResponse` and the supporting `BlackmanHarrisKernel`).
// The Morse keyer uses these to shape the on/off transition of each dot
// and dash — a hard square would produce audible "key clicks", a
// Blackman-Harris-shaped ramp puts the sideband energy well below the
// receiver bandwidth.

import Darwin
import MRCore

@inline(__always)
private func bhKernel(_ x: Double) -> Double {
    // Three different angles: plain cos for each (no sin/cos pair).
    DspK.blackmanHarrisA0
        - DspK.blackmanHarrisA1 * cos(MathK.twoPi * x * 1.0)
        + DspK.blackmanHarrisA2 * cos(MathK.twoPi * x * 2.0)
        - DspK.blackmanHarrisA3 * cos(MathK.twoPi * x * 3.0)
}

/// Returns a length-`len` array that monotonically rises from 0 to 1,
/// shaped as the integral of a 4-term Blackman-Harris window. Used as the
/// "ramp on" curve; the keyer reverses it for "ramp off".
///
/// The output is normalized so the final sample equals exactly 1.0 (so
/// the dot/dash sustain section that follows continues at full amplitude
/// without a discontinuity).
public func blackmanHarrisStep(_ len: Int) -> [Float] {
    // Pascal: VCL/MorseKey.pas::BlackmanHarrisStepResponse — generate the
    // window kernel, integrate it (cumulative sum), normalize the tail
    // value to 1. Computing in double then narrowing to float keeps the
    // tail-normalization error well below float epsilon.
    if len <= 0 {
        return []
    }
    var acc = [Double](repeating: 0, count: len)
    for i in 0..<len {
        acc[i] = bhKernel(Double(i) / Double(len))
    }
    for i in stride(from: 1, to: len, by: 1) {
        acc[i] += acc[i - 1]
    }
    let tail = acc[len - 1]
    if tail == 0.0 {
        // Degenerate (len=1, kernel(0) = a0 - a1 + a2 - a3). Defensive
        // path: return all ones so the keyer still produces a valid
        // envelope.
        return [Float](repeating: 1.0, count: len)
    }
    let inv = 1.0 / tail
    var out = [Float](repeating: 0, count: len)
    for i in 0..<len {
        out[i] = Float(acc[i] * inv)
    }
    // Pin the final sample exactly to 1.0 so downstream "AddOn" stages
    // do not see an off-by-one-ULP discontinuity.
    out[len - 1] = 1.0
    return out
}
