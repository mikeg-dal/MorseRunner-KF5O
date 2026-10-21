// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of QrnStn.pas (C++ src/simulation/QrnStation). A short burst of
// atmospheric noise: a sparse spike envelope up to ~1 s long that frees
// itself once keyed out.

import Darwin
import MRCore

public final class QrnStation: Station {
    /// True once the burst's envelope has been fully consumed.
    public private(set) var isFinished = false

    override init(engine: any Engine) {
        super.init(engine: engine)
        let rng = engine.random
        let bufSize = engine.bufferSize

        precondition(bufSize > 0, "QrnStation needs a positive engine buffer size")

        // Pascal: Dur := SecondsToBlocks(Random) * Ini.BufSize. Inline,
        // as in the C++ QrnStation.cpp constructor: the seconds value is
        // the Float draw widened to Double, then Double(seconds) · SR /
        // bufSize, round half to even. Same arithmetic as
        // `qrmSecondsToBlocks` but deliberately not shared with it (or
        // with DxOperator's fixed-512 variant): each copy tracks its own
        // C++ call site.
        let seconds = Double(rng.uniform01())
        let blocks = delphiRound(seconds * Double(AudioK.sampleRate) / Double(bufSize))
        let durSamples = blocks * bufSize

        envelope = [Float](repeating: 0.0, count: durSamples)

        // Pascal: Amplitude := 1E5 * Power(10, 2*Random).
        setAmplitude(DspK.qrnBurstAmpBase * pow(Float(10.0), Float(2.0) * rng.uniform01()))

        // Pascal: per-sample 1% chance of (Random-0.5)*Amplitude.
        let a = amplitude
        for i in 0..<durSamples {
            if rng.uniform01() < DspK.qrnBurstEnvelopeSpikeProb {
                envelope[i] = (rng.uniform01() - 0.5) * a
            }
        }

        state = .sending
    }

    override func processEvent(_ event: StationEvent) {
        // Pascal: if AEvent = evMsgSent then Free. Ownership is held by
        // StationCollection; we flag ourselves for the next sweep.
        if event == .msgSent {
            isFinished = true
        }
    }
}
