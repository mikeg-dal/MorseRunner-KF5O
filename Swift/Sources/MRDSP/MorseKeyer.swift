// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/dsp/MorseKeyer.cpp (VCL/MorseKey.pas). Encodes a free-text
// message into the keyer alphabet (./- /~) and renders an amplitude
// envelope at the configured WPM and sample rate.
//
// Timing math (verbatim from the original):
//
//   SamplesInUnit = round(0.1 · SR · 12 / WPM)
//
// One "unit" is a dot length. A dot is one unit on + one unit off, a
// dash is three units on + one unit off, an inter-character space adds
// two extra units of silence, and the '~' end-of-message marker collapses
// the trailing inter-character silence to a single unit (so successive
// messages don't accumulate trailing gap).

import MRCore

public final class MorseKeyer {
    private var sampleRate: Int
    private var wpm: Int
    public private(set) var samplesPerUnit = 0
    public private(set) var rampSamples = 0
    private var rampOn: [Float] = []
    private var rampOff: [Float] = []

    /// `sampleRate` is the audio sample rate (typically AudioK.sampleRate).
    /// `wpm` is words-per-minute in the PARIS reference.
    ///
    /// - Precondition: `sampleRate > 0` and `wpm > 0` (the unit length
    ///   divides by wpm); the setters ignore such values instead.
    public init(sampleRate: Int, wpm: Int) {
        precondition(sampleRate > 0, "MorseKeyer: sampleRate must be positive")
        precondition(wpm > 0, "MorseKeyer: wpm must be positive")
        self.sampleRate = sampleRate
        self.wpm = wpm
        recomputeTiming()
        rebuildRamps()
    }

    public func setWpm(_ wpm: Int) {
        if wpm == self.wpm || wpm <= 0 {
            return
        }
        self.wpm = wpm
        recomputeTiming()
    }

    public func setSampleRate(_ sampleRate: Int) {
        if sampleRate == self.sampleRate || sampleRate <= 0 {
            return
        }
        self.sampleRate = sampleRate
        recomputeTiming()
        rebuildRamps()
    }

    private func recomputeTiming() {
        // SamplesInUnit = round(0.1 · SR · 12 / WPM). For SR = 11025, WPM = 30:
        // SamplesInUnit = round(441) = 441 — matches Delphi byte-for-byte.
        let samples = DspK.morseUnitSecondsCoef
            * Double(sampleRate)
            * Double(DspK.morseUnitsPerWpmRef)
            / Double(wpm)
        samplesPerUnit = delphiRound(samples)
    }

    private func rebuildRamps() {
        // RampLen = round(2.7 · RiseTime · SR). RiseTime = 5 ms → RampLen ≈ 149
        // samples at SR = 11025. Pascal: VCL/MorseKey.pas::MakeRamp.
        let len = DspK.blackmanHarrisStretch * DspK.riseTimeSeconds * Double(sampleRate)
        rampSamples = delphiRound(len)
        rampOn = blackmanHarrisStep(rampSamples)
        // Off-ramp is the on-ramp reversed (so the keying envelope is
        // perfectly symmetric — important for spectral cleanliness).
        rampOff = Array(rampOn.reversed())
    }

    /// Pascal: VCL/MorseKey.pas::GetEnvelope counts units before allocating.
    /// '.': 2 units on+off, '-': 4 units on+off, ' ': 2 units silence,
    /// '~': 1 unit silence (terminal short-gap).
    private static func countUnits(_ morse: [UInt8]) -> Int {
        var n = 0
        for c in morse {
            switch c {
            case dot: n += 2
            case dash: n += 4
            case space: n += 2
            case tilde: n += 1
            default: break
            }
        }
        return n
    }

    private static let dot = UInt8(ascii: ".")
    private static let dash = UInt8(ascii: "-")
    private static let space = UInt8(ascii: " ")
    private static let tilde = UInt8(ascii: "~")

    /// Renders `text` into a float envelope (range [0, 1]). `text` may be
    /// plain ASCII (characters without a Morse mapping are skipped) or
    /// already in the encoded alphabet.
    public func renderEnvelope(_ text: String) -> [Float] {
        // Auto-detect whether the input is already encoded morse
        // (./- /~/space) or free text. If every char is in the morse
        // alphabet, treat it as already encoded; otherwise run it through
        // encodeMessage first.
        if samplesPerUnit <= 0 || rampSamples <= 0 {
            return []
        }
        let bytes = Array(text.utf8)
        var allEncoded = !bytes.isEmpty
        for c in bytes where !(c == Self.dot || c == Self.dash || c == Self.space || c == Self.tilde) {
            allEncoded = false
            break
        }
        let morse: [UInt8] = allEncoded ? bytes : Array(encodeMessage(text).utf8)
        if morse.isEmpty {
            return []
        }

        let totalUnits = Self.countUnits(morse)
        let unitSamples = samplesPerUnit
        let ramp = rampSamples

        // Pascal: VCL/MorseKey.pas — buffer = ceil(needed / bufSize) * bufSize.
        // We return exactly the number of samples needed and let the
        // caller pad. trueLen is the audio-visible envelope length.
        let trueLen = totalUnits * unitSamples + ramp
        if trueLen <= 0 {
            return []
        }

        var out = [Float](repeating: 0, count: trueLen)

        // Pascal keeps a signed write pointer. Above ~88 WPM a unit is
        // shorter than the 149-sample ramp, so `Dur*SamplesInUnit - RampLen`
        // goes negative: AddOn writes nothing, AddOn/AddOff move the pointer
        // back, and the next ramp overwrites the tail of the previous one.
        // Writes are bounds-checked as a safety net; for every WPM in
        // 10..120 Pascal's arithmetic already stays inside trueLen.
        var pos = 0
        let outLen = trueLen
        let rampOn = self.rampOn
        let rampOff = self.rampOff

        out.withUnsafeMutableBufferPointer { o in
            func writeRamp(_ r: [Float]) {
                let n = r.count
                for i in 0..<n {
                    let at = pos + i
                    if at >= 0 && at < outLen {
                        o[at] = r[i]
                    }
                }
                pos += n
            }
            func addOn(_ durUnits: Int) {
                // Pascal: `AddOn(Dur)` fills `Dur*SamplesInUnit - RampLen`
                // samples at 1.0. The ramp before/after eats the rest.
                let span = durUnits * unitSamples - ramp
                var i = 0
                while i < span {
                    let at = pos + i
                    if at >= 0 && at < outLen {
                        o[at] = 1.0
                    }
                    i += 1
                }
                pos += span
            }
            func addOff(_ durUnits: Int) {
                // Off-state: only move the pointer; the buffer is zeroed.
                pos += durUnits * unitSamples - ramp
            }

            for c in morse {
                switch c {
                case Self.dot:
                    writeRamp(rampOn)
                    addOn(1)
                    writeRamp(rampOff)
                    addOff(1)
                case Self.dash:
                    writeRamp(rampOn)
                    addOn(3)
                    writeRamp(rampOff)
                    addOff(1)
                case Self.space:
                    addOff(2)
                case Self.tilde:
                    addOff(1)
                default:
                    break
                }
            }
        }
        return out
    }
}
