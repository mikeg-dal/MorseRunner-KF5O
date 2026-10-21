// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Station.pas TStation (C++ src/simulation/Station). Abstract
// base for every audible source in the simulation — the player
// (MyStation), DX callers (DxStation), and the interferer stations
// (QrnStation / QrmStation).
//
// Responsibilities:
//   - Hold the rendered keying envelope and a cursor that the Contest
//     consumes block-by-block via getBlock().
//   - Maintain a BFO phase accumulator advanced per audio sample (used
//     by Contest to mix the station's envelope at the station's
//     individual offset from the user's tuning).
//   - Receive events (Timeout, MsgSent, MeStarted, MeFinished) from
//     the Contest and dispatch them to the concrete subclass.
//   - Keep a timer-down counter (TimeOut) in audio-block units; the
//     Contest decrements it once per render block via tick().

import MRCore
import MRDSP

public enum StationState: Int, Sendable {
    case listening = 0, copying, preparingToSend, sending
}

public enum StationEvent: Int, Sendable {
    case timeout = 0, msgSent, meStarted, meFinished
}

/// Sentinel "never trigger a timeout" value: the C++ `INT_MAX` (32-bit),
/// kept so traces print identically.
public let kNeverTimeout = Int(Int32.max)

public class Station {
    /// Not owned: the engine (Contest) owns every station — the player
    /// directly, the rest through its StationCollection — so it always
    /// outlives them. Unowned (not weak) because a station without its
    /// engine is a programming error and should trap, not silently go
    /// quiet. Anything that builds a station by hand (tests with a fake
    /// engine) must keep the engine alive for as long as it uses the
    /// station.
    unowned let engine: any Engine
    let keyer: MorseKeyer
    var envelope: [Float] = []
    var sendPos = 0
    var accumulatedText = ""

    public internal(set) var timeout = kNeverTimeout
    public internal(set) var msg = MessageSet()
    public internal(set) var state: StationState = .listening

    public internal(set) var myCall = ""
    public internal(set) var hisCall = ""
    public internal(set) var rst = 599
    public internal(set) var nr = 1
    public internal(set) var wpm = 30
    public private(set) var pitchHz = 600
    var nrWithError = false
    public internal(set) var amplitude: Float = 1.0

    // BFO phase accumulator. Double because the per-sample delta is
    // small and float accumulates audible drift over multi-second runs.
    public private(set) var bfoPhase: Double = 0.0
    var bfoPhaseDelta: Double = 0.0

    init(engine: any Engine) {
        self.engine = engine
        keyer = MorseKeyer(sampleRate: AudioK.sampleRate, wpm: 30)
        recomputeBfoDelta()
    }

    // Mutators are internal: only the engine drives stations. The app
    // reads them through the public read-only properties above.

    /// Subclasses dispatch on event kind. Contest calls this once per
    /// event from its render loop.
    func processEvent(_ event: StationEvent) {
        fatalError("Station.processEvent is abstract")
    }

    // MARK: setters (C++ inline setters)

    func setPitchHz(_ hz: Int) {
        pitchHz = hz
        recomputeBfoDelta()
    }

    func setWpm(_ w: Int) {
        wpm = w
        keyer.setWpm(w)
    }

    func setMyCall(_ c: String) { myCall = c }
    func setHisCall(_ c: String) { hisCall = c }
    func setRst(_ r: Int) { rst = r }
    func setNr(_ n: Int) { nr = n }
    func setAmplitude(_ a: Float) { amplitude = a }
    func setTimeout(_ blocks: Int) { timeout = blocks }

    var envelopeExhausted: Bool { sendPos >= envelope.count }

    private func recomputeBfoDelta() {
        bfoPhaseDelta = MathK.twoPi * Double(pitchHz) / Double(AudioK.sampleRate)
    }

    /// Advances the BFO phase one sample and returns the phase before
    /// the advance.
    @discardableResult
    func tickBfoPhase() -> Double {
        let result = bfoPhase
        bfoPhase += bfoPhaseDelta
        if bfoPhase > MathK.twoPi {
            bfoPhase -= MathK.twoPi
        }
        return result
    }

    /// Pulls up to `out.count` samples from the envelope into `out`.
    /// Samples beyond the envelope's length are left untouched. Returns
    /// the number of samples written (0 when not Sending).
    @discardableResult
    func getBlock(_ out: UnsafeMutableBufferPointer<Float>) -> Int {
        if state != .sending || envelope.isEmpty {
            return 0
        }
        let remaining = sendPos < envelope.count ? envelope.count - sendPos : 0
        let copied = min(remaining, out.count)
        if copied > 0 {
            envelope.withUnsafeBufferPointer { env in
                for i in 0..<copied {
                    out[i] = env[sendPos + i]
                }
            }
            sendPos += copied
        }
        if sendPos >= envelope.count {
            // Envelope fully consumed; tick() fires MsgSent next.
            envelope.removeAll(keepingCapacity: false)
            sendPos = 0
        }
        return copied
    }

    /// Array convenience for getBlock.
    @discardableResult
    final func getBlock(_ out: inout [Float]) -> Int {
        out.withUnsafeMutableBufferPointer { getBlock($0) }
    }

    /// Queue an outgoing message. Substitutes placeholders and renders
    /// the envelope via the MorseKeyer. The state transitions to Sending.
    func sendMsg(_ m: Message) {
        // Pascal: if Envelope = nil then Msg := [] — wipe the message set
        // whenever we start a new transmission from idle.
        if envelope.isEmpty {
            msg.reset()
        }
        if m == .none {
            state = .listening
            return
        }
        msg.insert(m)

        let tmpl = m.template
        if !tmpl.isEmpty {
            sendText(tmpl)
        }
    }

    func sendText(_ text: String) {
        // Pascal TStation.SendText:
        //   AMsg := StringReplace(AMsg, '<#>', NrAsText, []);              // first, may carry the LID error
        //   AMsg := StringReplace(AMsg, '<#>', NrAsText, [rfReplaceAll]);  // the rest, one fresh value
        // so in "R <#> <#>" (R_NR2) only the first copy has the error and
        // each copy rolls its own cut-number style.
        var assembled = text.bytes
        let token = "<#>".bytes
        if let first = ByteString.firstIndex(of: token, in: assembled) {
            assembled.replaceSubrange(first..<(first + 3), with: nrAsText(nrWithError).bytes)
            if ByteString.firstIndex(of: token, in: assembled) != nil {
                assembled = ByteString.replacingAll(token, with: nrAsText(false).bytes, in: assembled)
            }
        }

        // `<my>` is the SENDING station's call (always own).
        assembled = ByteString.replacingAll("<my>".bytes, with: myCall.bytes, in: assembled)
        // Pascal's base SendText leaves `<his>` in place (its substitution
        // is commented out) and the keyer has no code for '<', 'h', 'i',
        // 's' or '>', so it keys as nothing: QRM's "<his>  QSY QSY" is
        // heard as "QSY QSY". MyStation splits around `<his>` itself and
        // never gets here with the token.
        assembled = ByteString.replacingAll("<his>".bytes, with: [], in: assembled)

        if accumulatedText.isEmpty {
            accumulatedText = assembled.asString
        } else {
            accumulatedText += " " + assembled.asString
        }
        sendMorse(encodeMessage(accumulatedText))
    }

    func sendMorse(_ morse: String) {
        // Reset the cursor and BFO if we're starting from idle (Pascal:
        // `if Envelope = nil then begin SendPos := 0; FBfo := 0`).
        if envelope.isEmpty {
            sendPos = 0
            bfoPhase = 0.0
        }
        keyer.setWpm(wpm)
        envelope = keyer.renderEnvelope(morse)
        let a = amplitude
        for i in envelope.indices {
            envelope[i] *= a
        }
        state = .sending
        timeout = kNeverTimeout
    }

    /// Per-block timer tick (Pascal Station.pas::Tick).
    ///   - Sending and the envelope is gone: → Listening, fire MsgSent.
    ///   - Else if not Sending: decrement TimeOut, fire Timeout at zero.
    func tick() {
        if state == .sending && envelope.isEmpty {
            accumulatedText = ""
            state = .listening
            processEvent(.msgSent)
        } else if state != .sending {
            if timeout > -1 && timeout != kNeverTimeout {
                timeout -= 1
            }
            if timeout == 0 {
                processEvent(.timeout)
            }
        }
    }

    /// Builds the NrAsText string for substituting `<#>` in templates.
    func nrAsText(_ injectLidError: Bool) -> String {
        let opts = NrFormatOptions(rst: rst, nr: nr,
                                   hstMode: engine.runMode == .hst,
                                   lidError: injectLidError)
        nrWithError = false  // consume the flag
        return MRSimulation.nrAsText(opts, engine.random)
    }
}
