// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/Agc.cpp (VCL/VolumCtl.pas, TVolumeControl). Look-ahead
// AGC with a Blackman-Harris-style attack shape and symmetric hold. The
// envelope is computed in log-magnitude space (so the attack shape is
// additive rather than multiplicative) and the gain curve is the standard
//
//     gain(env) = MaxOut · (1 - exp(-env / Beta)) / env
//
// which saturates smoothly at MaxOut while staying linear near the noise
// floor. Beta is solved from CalcBeta so that the configured NoiseIn maps
// to NoiseOut at unity-gain.

import Darwin
import MRCore

public final class Agc {
    /// Added to |x| before the log so silence maps to a finite value.
    static let envelopeFloor: Float = 1.0e-10
    /// ln(envelopeFloor): the starting maximum of the envelope search.
    /// Kept as the C++ literal; it equals `log(envelopeFloor)` bit for bit
    /// (logf(1e-10f) = -23.025851f, checked by a unit test), so the search
    /// can never return less than the floor itself.
    static let envelopeFloorLog: Float = -23.025851

    public private(set) var maxOut: Float = 20000.0
    private var noiseIn: Float = 1.0
    private var noiseOut: Float = 2000.0
    private var beta: Float = 1.0
    private var defaultGain: Float = 2000.0
    private var attackSamples = 28
    private var holdSamples = 28
    private var len = 0
    private var bufIdx = 0
    public var enabled = true
    public private(set) var isOverload = false

    private var realBuf: [Float] = []
    private var magBuf: [Float] = []
    private var attackShape: [Float] = []

    public init() {
        rebuildAttackShape()
        recomputeBeta()
    }

    public func setEnabled(_ on: Bool) { enabled = on }

    public func setNoiseInDb(_ db: Float) {
        // Pascal: FNoiseIn := Power(10, 0.05 * Value).
        noiseIn = pow(Float(10.0), 0.05 * db)
        recomputeBeta()
    }

    public func setNoiseOutDb(_ db: Float) {
        // Pascal clamps NoiseOut to 25% of MaxOut to keep the AGC curve's
        // exponent well-defined.
        let candidate = pow(Float(10.0), 0.05 * db)
        noiseOut = min(0.25 * maxOut, candidate)
        recomputeBeta()
    }

    public func setMaxOut(_ maxOut: Float) {
        if maxOut <= 0.0 {
            return
        }
        self.maxOut = maxOut
        recomputeBeta()
    }

    public func setAttackSamples(_ n: Int) {
        attackSamples = max(1, n)
        rebuildAttackShape()
    }

    public func setHoldSamples(_ n: Int) {
        holdSamples = max(1, n)
        rebuildAttackShape()
    }

    private func recomputeBeta() {
        // Pascal: FBeta := FNoiseIn / Ln(FMaxOut / (FMaxOut - FNoiseOut)).
        // This solves NoiseOut = MaxOut · (1 - exp(-NoiseIn / Beta)) for
        // Beta, so the linear-region gain matches the requested ratio.
        if noiseOut < maxOut {
            beta = noiseIn / log(maxOut / (maxOut - noiseOut))
        } else {
            beta = noiseIn
        }
        defaultGain = (noiseIn > 0.0) ? (noiseOut / noiseIn) : 1.0
    }

    private func rebuildAttackShape() {
        // Pascal: FLen := 2 * (FAttackSamples + FHoldSamples) + 1; attack
        // shape is a half-cosine rising window in log space, mirrored on
        // the trailing side so the look-ahead and look-back are symmetric.
        len = 2 * (attackSamples + holdSamples) + 1
        attackShape = [Float](repeating: 0, count: len)
        for i in 0..<attackSamples {
            let phase = Double(i + 1) * MathK.pi / Double(attackSamples + 1)
            let val = Float(log(0.5 - 0.5 * cos(phase)))  // cos only
            attackShape[i] = val
            attackShape[len - 1 - i] = val
        }
        reset()
    }

    /// Drops all delay-line state. Called by the Contest engine on
    /// run-mode transitions.
    public func reset() {
        realBuf = [Float](repeating: 0, count: len)
        magBuf = [Float](repeating: 0, count: len)
        bufIdx = 0
    }

    @inline(__always)
    private func calcAgcGain(_ mag: UnsafeBufferPointer<Float>,
                             _ shape: UnsafeBufferPointer<Float>) -> Float {
        // Look ±len/2 around the current sample; take the maximum of
        // log-mag plus the attack-shape weight. The exponentiation then
        // converts back to linear envelope; the standard 1-exp(-env/Beta)
        // soft-knee curve gives the gain.
        var envelLog = Self.envelopeFloorLog  // Pascal's "envelope floor".
        var idx = bufIdx
        for wi in 0..<len {
            let sample = mag[idx] + shape[wi]
            if sample > envelLog {
                envelLog = sample
            }
            idx += 1
            if idx == len {
                idx = 0
            }
        }
        let envel = exp(envelLog)
        return maxOut * (1.0 - exp(-envel / beta)) / envel
    }

    /// Processes a block of real samples in place. When bypassed, samples
    /// get the default gain and are clamped to ±maxOut.
    public func process(_ data: UnsafeMutableBufferPointer<Float>) {
        isOverload = false
        if enabled {
            let len = self.len
            realBuf.withUnsafeMutableBufferPointer { real in
                magBuf.withUnsafeMutableBufferPointer { mag in
                    attackShape.withUnsafeBufferPointer { shape in
                        for k in 0..<data.count {
                            // applyAgc
                            let v = data[k]
                            real[bufIdx] = v
                            mag[bufIdx] = log(abs(v) + Self.envelopeFloor)
                            // (bufIdx + 1) % len and (bufIdx + len/2) % len
                            // without the divisions: bufIdx < len.
                            bufIdx += 1
                            if bufIdx == len { bufIdx = 0 }
                            var mid = bufIdx + (len / 2)
                            if mid >= len { mid -= len }
                            data[k] = real[mid] * calcAgcGain(UnsafeBufferPointer(mag), shape)
                        }
                    }
                }
            }
        } else {
            for k in 0..<data.count {
                let scaled = data[k] * defaultGain
                // std::clamp(v, lo, hi)
                let lo = -maxOut
                let hi = maxOut
                let clamped = scaled < lo ? lo : (hi < scaled ? hi : scaled)
                if abs(clamped) == maxOut {
                    isOverload = true
                }
                data[k] = clamped
            }
        }
    }

    public func process(_ data: inout [Float]) {
        data.withUnsafeMutableBufferPointer { process($0) }
    }
}
