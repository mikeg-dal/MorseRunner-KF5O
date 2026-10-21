// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of QrmStn.pas (C++ src/simulation/QrmStation). A neighbouring
// station the player can hear but isn't part of the contest with. Sends
// one of QRL?, QRL? QRL?, long CQ, or QSY at construction, then on
// timeout re-keys a long CQ until its patience (1..5) runs out.
//
// Spawned by Contest at DspK.qrmSpawnPerBlockProb (0.0002) per block.

import MRCore

/// Pascal: SecondsToBlocks(4) gives the baseline reload interval before
/// the QrmStation re-keys a long CQ.
private let qrmReloadSeconds: Float = 4.0
private let qrmReloadJitter: Float = 2.0

/// Pascal SecondsToBlocks as the C++ QrmStation.cpp anonymous-namespace
/// `secondsToBlocks(float, int)` computes it: Double(seconds) · SR /
/// bufSize with the ENGINE's buffer size, round half to even. Kept
/// separate from DxOperator's (fixed 512-sample buffer) and from
/// `AudioK.secondsToBlocks` (different operand order and rounding); see
/// `dxSecondsToBlocksAtDefaultBuffer`.
private func qrmSecondsToBlocks(_ seconds: Float, bufSize: Int) -> Int {
    precondition(bufSize > 0, "QrmStation needs a positive engine buffer size")
    return delphiRound(Double(seconds) * Double(AudioK.sampleRate) / Double(bufSize))
}

public final class QrmStation: Station {
    private var patience = 1
    public private(set) var isFinished = false

    /// `randomCall` is the callsign drawn from the database (or fallback
    /// "P29SX"); the station broadcasts using it as `<my>`.
    init(engine: any Engine, call randomCall: String) {
        super.init(engine: engine)
        let rng = engine.random

        // Pascal: Patience := 1 + Random(5).
        patience = 1 + rng.uniformInt(5)

        setMyCall(randomCall)
        setHisCall(engine.myCallsign)

        // Pascal: Amplitude := 5000 + 25000 * Random.
        setAmplitude(DspK.qrmAmpBase + DspK.qrmAmpRange * rng.uniform01())

        // Pascal: Pitch := Round(RndGaussLim(0, 300)).
        setPitchHz(delphiRound(rng.gaussLim(0.0, DspK.qrmPitchSpreadHz)))

        // Pascal: Wpm := 30 + Random(20).
        setWpm(DspK.qrmWpmBase + rng.uniformInt(DspK.qrmWpmRange))

        // Pascal: case Random(7) of ...
        switch rng.uniformInt(7) {
        case 0: sendMsg(.qrl)
        case 1, 2: sendMsg(.qrl2)
        case 3, 4, 5: sendMsg(.longCq)
        case 6: sendMsg(.qsy)
        default: sendMsg(.longCq)
        }
    }

    override func processEvent(_ event: StationEvent) {
        let rng = engine.random
        let bufSize = engine.bufferSize

        switch event {
        case .msgSent:
            patience -= 1
            if patience <= 0 {
                isFinished = true
                return
            }
            // Pascal: Timeout := Round(RndGaussLim(SecondsToBlocks(4), 2)).
            let base = qrmSecondsToBlocks(qrmReloadSeconds, bufSize: bufSize)
            setTimeout(delphiRound(rng.gaussLim(Float(base), qrmReloadJitter)))
        case .timeout:
            sendMsg(.longCq)
        case .meStarted, .meFinished:
            // QrmStations ignore player activity — Pascal omits these arms.
            break
        }
    }
}
