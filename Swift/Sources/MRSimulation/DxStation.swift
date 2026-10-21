// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of DxStn.pas TDxStation (C++ src/simulation/DxStation). Each
// caller in the simulation owns one of these — the audible "caller"
// trying to work the player. On construction we draw random Skills
// (1..3), Amplitude, Pitch, WPM, RST, NR, Qsb bandwidth, and an optional
// LID-flagged NR corruption from the distributions in
// DxStn.pas::CreateStation.
//
// Per-block side effect: getBlock() applies the per-station Qsb
// (Rayleigh fading) on top of the base envelope.

import MRCore
import MRDSP

public final class DxStation: Station {
    /// The station's operator (Pascal TDxStation.Oper): the QSO state
    /// machine deciding what this caller sends next.
    public let dxOperator: DxOperator
    private let qsb: Qsb
    private var released = false

    init(engine: any Engine, call heardCall: String) {
        // Draw order matters: the C++ constructs the operator (no draws
        // in NeedPrevEnd) and then the Qsb (whose warm-up draws) before
        // the constructor body.
        dxOperator = DxOperator(engine: engine)
        qsb = Qsb(bufSize: engine.bufferSize, rng: engine.random)
        super.init(engine: engine)

        let rng = engine.random

        // Pascal: HisCall := Ini.Call; MyCall := PickCall.
        setHisCall(engine.myCallsign)
        setMyCall(heardCall)

        // Pascal: Skills := 1 + Random(3).
        let skills = 1 + rng.uniformInt(3)
        dxOperator.skills = skills
        dxOperator.call = myCall
        dxOperator.setState(.needPrevEnd)

        // Pascal: NrWithError := Ini.Lids and (Random < 0.1).
        nrWithError = engine.lidsEnabled && rng.uniform01() < SimK.lidNrErrorProb

        setWpm(dxOperator.randomWpm())
        setNr(dxOperator.randomNumber())

        // Pascal: if Ini.Lids and (Random < 0.03) then RST := 559 + 10*Random(4); else 599.
        if engine.lidsEnabled && rng.uniform01() < SimK.lidRstErrorProb {
            setRst(SimK.lidRstBase + SimK.lidRstStep * rng.uniformInt(SimK.lidRstCount))
        } else {
            setRst(599)
        }

        // Pascal: Qsb.Bandwidth := 0.1 + Random/2; with 30% flutter chance,
        // bandwidth jumps to 3..33 Hz.
        var bw: Float = DspK.qsbBandwidthBase + rng.uniform01() * DspK.qsbBandwidthSpread
        if engine.flutterEnabled && rng.uniform01() < DspK.flutterProb {
            bw = DspK.flutterBwBase + rng.uniform01() * DspK.flutterBwSpread
        }
        qsb.setBandwidth(bw)

        // Pascal: Amplitude := 9000 + 18000 * (1 + RndUShaped).
        setAmplitude(SimK.dxAmpBase + SimK.dxAmpSpread * (1.0 + rng.uShaped()))

        // Pascal: Pitch := Round(RndGaussLim(0, 300)).
        setPitchHz(delphiRound(rng.gaussLim(0.0, SimK.dxPitchSpreadHz)))

        // Pascal: TimeOut := NEVER; State := stCopying.
        setTimeout(kNeverTimeout)
        state = .copying
    }

    /// True when the operator has finished (Done or Failed).
    public var isFinished: Bool {
        dxOperator.state == .done || dxOperator.state == .failed
    }

    /// Pascal frees a DX station when its operator gives up (osFailed),
    /// or when it is Done *and* its call matches the last logged QSO
    /// (TDxStation.DataToLastQso ends with Free). A Done station that
    /// never matches stays in the list, silent, until the next Run.
    var shouldRemove: Bool {
        released || dxOperator.state == .failed
    }

    func release() { released = true }

    override func processEvent(_ event: StationEvent) {
        if dxOperator.state == .done {
            return
        }

        switch event {
        case .msgSent:
            // If the player is already transmitting, wait for them to
            // finish (their evMeFinished drives us). Pascal: if
            // Tst.Me.State = stSending then TimeOut := NEVER else
            // TimeOut := Oper.GetReplyTimeout.
            setTimeout(engine.playerSending ? kNeverTimeout
                                            : dxOperator.replyTimeoutBlocks())

        case .timeout:
            if state == .listening {
                var noneSet = MessageSet()
                noneSet.insert(.none)
                dxOperator.onMessageReceived(noneSet)
                if dxOperator.state == .failed {
                    return
                }
                state = .preparingToSend
            }
            if state == .preparingToSend {
                var i = 0
                while i < dxOperator.repeatCount {
                    let reply = dxOperator.reply()
                    if reply != .none {
                        sendMsg(reply)
                    }
                    i += 1
                }
            }

        case .meFinished:
            if state != .sending {
                // Pascal: in stCopying the full FSM; in [stListening,
                // stPreparingToSend] only CQ/TU/NIL, else msgGarbage.
                if state == .copying {
                    dxOperator.onMessageReceived(engine.myLastMessage)
                } else {
                    let heard = engine.myLastMessage
                    if heard.contains(.cq) || heard.contains(.tu) || heard.contains(.nilMsg) {
                        dxOperator.onMessageReceived(heard)
                    } else {
                        var garbageOnly = MessageSet()
                        garbageOnly.insert(.garbage)
                        dxOperator.onMessageReceived(garbageOnly)
                    }
                }
                if dxOperator.state == .failed {
                    return
                }
                setTimeout(dxOperator.sendDelayBlocks())
                state = .preparingToSend
            }

        case .meStarted:
            // Player started transmitting again — switch to copy mode.
            if state != .sending {
                state = .copying
            }
            setTimeout(kNeverTimeout)
        }
    }

    @discardableResult
    override func getBlock(_ out: UnsafeMutableBufferPointer<Float>) -> Int {
        let written = super.getBlock(out)
        // Pascal: TDxStation.GetBlock invokes Qsb.ApplyTo if Ini.Qsb.
        if written > 0 && engine.qsbEnabled {
            qsb.applyTo(UnsafeMutableBufferPointer(rebasing: out[0..<written]))
        }
        return written
    }
}
