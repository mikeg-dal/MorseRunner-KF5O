// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of DxOper.pas TDxOperator (C++ src/simulation/DxOperator). The QSO
// state machine the DX stations follow.
//
//   NeedPrevEnd → NeedQso → NeedNr ┐
//                                  ├→ NeedCall ──┐
//                                  └→ NeedCallNr ┘
//                                                ↓
//                                             NeedEnd → Done
//
//   (Any state) → Failed   on patience exhaustion or contradiction
//
// Patience is decremented on every received message that doesn't
// advance the operator; reaching zero forces Failed. Entering NeedQso
// uses a Rayleigh-distributed patience with mean 4; other states use
// the constant fullPatience (5).

import MRCore

public enum OperatorState: Int, Sendable {
    case needPrevEnd = 0, needQso, needNr, needCall, needCallNr, needEnd, done, failed
}

/// Pascal RndFunc.pas SecondsToBlocks = Round(DEFAULTRATE / BufSize * Sec),
/// as the C++ DxOperator.cpp anonymous-namespace `secondsToBlocks(float)`
/// computes it: Double(seconds) · SR / **512** (the default buffer, not
/// the engine's), round half to even.
///
/// Not interchangeable with `qrmSecondsToBlocks` (engine buffer size),
/// QrnStation's burst length (engine buffer size) or
/// `AudioK.secondsToBlocks` (SR / bufSize first, then × seconds, its own
/// rounding): the buffer size, operand order or rounding differ, and
/// each matches its own C++ call site bit for bit.
private func dxSecondsToBlocksAtDefaultBuffer(_ seconds: Float) -> Int {
    delphiRound(Double(seconds) * Double(AudioK.sampleRate)
                / Double(AudioK.defaultBufferSamples))
}

public final class DxOperator {
    /// Not owned: the operator belongs to a DxStation, which the engine
    /// owns (see Station.engine).
    unowned let engine: any Engine
    /// The DX's own callsign.
    public internal(set) var call = ""
    /// Operator skill level, 1...3 as drawn by DxStation. Other values
    /// are not rejected (the C++ doesn't): `replyTimeoutBlocks` uses
    /// `6 - skills` and `randomNumber` scales by it.
    public internal(set) var skills = 1
    public private(set) var patience = 0
    public private(set) var repeatCount = 1
    public private(set) var state: OperatorState = .needPrevEnd

    init(engine: any Engine) {
        self.engine = engine
        setState(.needPrevEnd)
    }

    /// Pascal SetState: also recomputes patience and repeat count.
    func setState(_ newState: OperatorState) {
        state = newState
        if newState == .needQso {
            // Pascal: Patience := Round(RndRayleigh(4)).
            patience = delphiRound(engine.random.rayleigh(SimK.needQsoPatienceMean))
        } else {
            patience = SimK.fullPatience
        }
        // Repeat count: 10% chance of 2 only when entering NeedQso and not
        // in Single / HST modes.
        repeatCount = 1
        if newState == .needQso {
            let mode = engine.runMode
            if mode != .single && mode != .hst && engine.random.uniform01() < SimK.repeatProb {
                repeatCount = SimK.repeatCount
            }
        }
    }

    /// Pascal TDxOperator.GetWpm (C++ getWpm): the engine's speed in HST,
    /// otherwise a uniform draw in [wpm/2, wpm]. Draws once outside HST.
    func randomWpm() -> Int {
        if engine.runMode == .hst {
            return engine.targetWpm
        }
        // Pascal: round(Wpm * 0.5 * (1 + Random)).
        let w = Double(engine.targetWpm) * 0.5 * (1.0 + Double(engine.random.uniform01()))
        return delphiRound(w)
    }

    /// Pascal TDxOperator.GetNumber (C++ getNumber): the serial number
    /// this DX sends, growing with contest time and skill. One draw.
    func randomNumber() -> Int {
        // Pascal: 1 + Round(Random * Tst.Minute * Skills).
        let n = Double(engine.random.uniform01()) * Double(engine.currentMinute) * Double(skills)
        return 1 + delphiRound(n)
    }

    /// Pascal TDxOperator.GetSendDelay (C++ getSendDelayBlocks), in
    /// blocks: NEVER in NeedPrevEnd (no draw), otherwise one draw.
    func sendDelayBlocks() -> Int {
        if state == .needPrevEnd {
            // Pascal returns the literal NEVER (MAXINT).
            return kNeverTimeout
        }
        if engine.runMode == .hst {
            precondition(engine.targetWpm > 0, "HST send delay divides by targetWpm, which must be >= 1")
            let u = engine.random.uniform01()
            let s: Float = 0.05 + 0.5 * u * 10.0 / Float(engine.targetWpm)
            return dxSecondsToBlocksAtDefaultBuffer(s)
        }
        // Non-HST: 100 ms .. 600 ms.
        let u = engine.random.uniform01()
        let s: Float = 0.1 + 0.5 * u
        return dxSecondsToBlocksAtDefaultBuffer(s)
    }

    /// Pascal TDxOperator.GetReplyTimeout (C++ getReplyTimeoutBlocks),
    /// in blocks, at least 1. Draws through gaussLim.
    func replyTimeoutBlocks() -> Int {
        let blocks: Int
        if engine.runMode == .hst {
            precondition(engine.targetWpm > 0, "HST reply timeout divides by targetWpm, which must be >= 1")
            // Pascal: SecondsToBlocks(60 / Wpm).
            blocks = dxSecondsToBlocksAtDefaultBuffer(Float(60.0) / Float(engine.targetWpm))
        } else {
            // Pascal: SecondsToBlocks(6 - Skills).
            blocks = dxSecondsToBlocksAtDefaultBuffer(Float(6 - skills))
        }
        // Pascal: Round(RndGaussLim(Result, Result/2)).
        let jittered = engine.random.gaussLim(Float(blocks), Float(blocks) / 2.0)
        return max(1, delphiRound(jittered))
    }

    private func decrementPatience() {
        if state == .done {
            return
        }
        patience -= 1
        if patience < 1 {
            state = .failed
        }
    }

    private func checkHeardCall() -> CallMatch {
        let opts = IsMyCallOptions(mine: call, his: engine.heardCallsign,
                                   lidsMode: engine.lidsEnabled)
        return isMyCall(opts, engine.random)
    }

    /// Pascal TDxOperator.MsgReceived.
    func onMessageReceived(_ heard: MessageSet) {
        // Pascal early-outs: msgCq and msgNil short-circuit.
        if heard.contains(.cq) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso: decrementPatience()
            case .needNr, .needCall, .needCallNr: state = .failed
            case .needEnd: state = .done
            default: break
            }
            return
        }
        if heard.contains(.nilMsg) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso: decrementPatience()
            case .needNr, .needCall, .needCallNr, .needEnd: state = .failed
            default: break
            }
            return
        }

        // msgHisCall: classify the heard call and branch by quality.
        if heard.contains(.hisCall) {
            switch checkHeardCall() {
            case .yes:
                if state == .needPrevEnd || state == .needQso {
                    setState(.needNr)
                } else if state == .needCallNr {
                    setState(.needNr)
                } else if state == .needCall {
                    setState(.needEnd)
                }
            case .almost:
                if state == .needPrevEnd || state == .needQso {
                    setState(.needCallNr)
                } else if state == .needNr {
                    setState(.needCallNr)
                } else if state == .needEnd {
                    setState(.needCall)
                }
            case .no:
                if state == .needQso {
                    state = .needPrevEnd
                } else if state == .needNr || state == .needCall || state == .needCallNr {
                    state = .failed
                } else if state == .needEnd {
                    state = .done
                }
            }
        }

        if heard.contains(.b4) {
            switch state {
            case .needPrevEnd, .needQso: setState(.needQso)
            case .needNr, .needEnd: state = .failed
            case .needCall, .needCallNr: break  // allow call correction
            default: break
            }
        }

        if heard.contains(.nr) {
            let inHst = engine.runMode == .hst
            let roll = engine.random.uniform01()
            switch state {
            case .needPrevEnd: break
            case .needQso: state = .needPrevEnd
            case .needNr:
                if roll < 0.9 || inHst {
                    setState(.needEnd)
                }
            case .needCallNr:
                if roll < 0.9 || inHst {
                    setState(.needCall)
                }
            default: break
            }
        }

        if heard.contains(.tu) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needEnd: state = .done
            default: break  // TU ignored mid-QSO
            }
        }

        // Pascal: `if (not Lids) and (AMsg = [msgGarbage]) then State :=
        //          osNeedPrevEnd`. Reset after pure interference.
        if !engine.lidsEnabled {
            if heard.contains(.garbage) && heard.count == 1 {
                state = .needPrevEnd
            }
        }

        // Pascal final line: any non-NeedPrevEnd state pays a patience cost.
        if state != .needPrevEnd {
            decrementPatience()
        }
    }

    /// Pascal TDxOperator.GetReply (C++ getReply). `.none` when no reply is appropriate.
    func reply() -> Message {
        let inHst = engine.runMode == .hst

        switch state {
        case .needPrevEnd, .done, .failed:
            return .none

        case .needQso:
            return .myCall

        case .needNr:
            // Pascal: ask for the NR after first attempt; otherwise AGN.
            if patience == SimK.fullPatience - 1 || engine.random.uniform01() < 0.3 {
                return .nrQm
            }
            return .agn

        case .needCall:
            if inHst || engine.random.uniform01() > 0.5 {
                return .deMyCallNr1
            }
            if engine.random.uniform01() > 0.25 {
                return .deMyCallNr2
            }
            return .myCallNr2

        case .needCallNr:
            if inHst || engine.random.uniform01() > 0.5 {
                return .deMyCall1
            }
            return .deMyCall2

        case .needEnd:
            if patience < SimK.fullPatience - 1 {
                return .nr
            }
            if inHst || engine.random.uniform01() < 0.9 {
                return .rNr
            }
            return .rNr2
        }
    }
}
