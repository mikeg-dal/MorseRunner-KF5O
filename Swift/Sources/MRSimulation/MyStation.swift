// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of MyStn.pas TMyStation (C++ src/simulation/MyStation). The
// player's transmitter.
//
// Why this exists as a separate class rather than reusing the base
// Station.sendText: the original supports "mid-air call correction".
// If the user is in the middle of keying "K1A?? 599..." and types a
// better guess, the still-pending part of the message must update to
// the new call without interrupting the keying. The original
// accomplishes this by splitting outgoing text into "pieces" around
// the `<his>` token. Each piece is rendered separately; before each
// piece begins, MyStation can swap in a different hisCall.

import MRCore
import MRDSP

public final class MyStation: Station {
    private static let hisCallToken = "<his>".bytes
    /// "@" is the sentinel for "his callsign" — at render time it expands
    /// to the current `hisCall`.
    private static let hisCallSentinel = "@"

    /// Fired from getBlock each time a piece finishes keying. Pascal
    /// TMyStation.GetBlock calls MainForm.Advance at that point. Runs on
    /// the simulation thread in the middle of Contest.renderNextBlock;
    /// see Contest.onPlayerPieceFinished.
    var pieceFinished: (() -> Void)?

    /// FIFO of pending pieces.
    private var pieces: [String] = []

    override init(engine: any Engine) {
        super.init(engine: engine)
        // Pascal: TMyStation.Init — sane defaults; Contest writes the real
        // values from Ini on startup.
        setMyCall("VE3NEA")
        setNr(1)
        setRst(599)
        setPitchHz(600)
        setWpm(30)
        setAmplitude(300_000.0)
    }

    public var pieceCount: Int { pieces.count }

    override func processEvent(_ event: StationEvent) {
        // Pascal: if AEvent = evMsgSent then Tst.OnMeFinishedSending.
        if event == .msgSent {
            engine.onPlayerFinishedSending()
        }
    }

    /// Abort whatever we're keying. Marks the current send as Garbage so
    /// DX stations interpret the partial transmission as unintelligible.
    func abortSend() {
        envelope.removeAll()
        sendPos = 0
        msg.reset()
        msg.insert(.garbage)
        accumulatedText = ""
        pieces.removeAll()
        state = .listening
        processEvent(.msgSent)
    }

    /// Overwrite the "last message I sent" set. Pascal Contest.GetAudio
    /// does `Me.Msg := [msgCQ]` before handing a fresh Single Calls / HST
    /// caller an evMeFinished.
    func setMsg(_ m: MessageSet) { msg = m }

    /// Splits incoming templates around `<his>` and queues the pieces.
    override func sendText(_ text: String) {
        var remaining = text.bytes
        while let pos = ByteString.firstIndex(of: Self.hisCallToken, in: remaining) {
            if pos > 0 {
                pieces.append(Array(remaining[0..<pos]).asString)
            }
            pieces.append(Self.hisCallSentinel)
            remaining.removeSubrange(0..<(pos + Self.hisCallToken.count))
        }
        if !remaining.isEmpty {
            pieces.append(remaining.asString)
        }

        if state != .sending {
            sendNextPiece()
            // Pascal: Tst.OnMeStartedSending.
            engine.onPlayerStartedSending()
        }
    }

    private func sendNextPiece() {
        guard let head = pieces.first else {
            return
        }
        // Clear the accumulated text from any previous piece so the keyer
        // renders just THIS piece. Pascal: MsgText := ''.
        accumulatedText = ""

        if head == Self.hisCallSentinel {
            // Expand the `<his>` slot with whatever hisCall is right now.
            // CallsFromKeyer: an external keyer sends the call, so key a
            // blank instead (Pascal keeps the call in WPX and HST).
            let mode = engine.runMode
            if engine.callsFromKeyer && mode != .hst && mode != .wpx {
                super.sendText(" ")
            } else {
                super.sendText(hisCall)
            }
        } else {
            super.sendText(head)
        }
    }

    /// When the current piece's envelope is exhausted, pops it and starts
    /// the next. Pascal: TMyStation.GetBlock pops Pieces[0], calls
    /// SendNextPiece, then MainForm.Advance.
    @discardableResult
    override func getBlock(_ out: UnsafeMutableBufferPointer<Float>) -> Int {
        let written = super.getBlock(out)
        if envelopeExhausted && !pieces.isEmpty {
            pieces.removeFirst()
            if !pieces.isEmpty {
                sendNextPiece()
            }
            pieceFinished?()
        }
        return written
    }

    /// Try to update the in-flight call. Returns true when the next
    /// pending `<his>` slot can adopt the new call (either we haven't
    /// started keying it yet, or the keyed prefix still matches and we
    /// can swap the envelope). Pascal: TMyStation.UpdateCallInMessage.
    @discardableResult
    func updateCallInMessage(_ newCall: String) -> Bool {
        if newCall.isEmpty {
            return false
        }

        // Are we sending the call right now?
        var ok = pieces.first == Self.hisCallSentinel

        // Is the part of the call already keyed the same in the new call?
        if ok {
            keyer.setWpm(wpm)
            var candidate = keyer.renderEnvelope(newCall)
            let a = amplitude
            for i in candidate.indices {
                candidate[i] *= a
            }
            ok = candidate.count >= sendPos && envelope.count >= sendPos
            var i = 0
            while ok && i < sendPos {
                ok = envelope[i] == candidate[i]
                i += 1
            }
            if ok {
                envelope = candidate
                setHisCall(newCall)
            }
        }

        // Could not correct the call being keyed, but another call is
        // queued for sending: use the new call there.
        if !ok {
            for i in pieces.indices.dropFirst() where pieces[i] == Self.hisCallSentinel {
                setHisCall(newCall)
                return true
            }
        }
        return ok
    }
}
