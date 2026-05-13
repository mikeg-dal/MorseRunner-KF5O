// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of MyStn.pas TMyStation. The player's transmitter.
//
// Why this exists as a separate class rather than reusing the base
// Station::sendText: the original supports "mid-air call correction".
// If the user is in the middle of keying "K1A?? 599..." and types a
// better guess, the still-pending part of the message must update to
// the new call without interrupting the keying. The original
// accomplishes this by splitting outgoing text into "pieces" around
// the `<his>` token. Each piece is rendered separately; before each
// piece begins, MyStation can swap in a different hisCall. We
// preserve that behavior verbatim.

#pragma once

#include "simulation/Station.h"

#include <deque>
#include <string>

namespace mr::sim {

class MyStation : public Station {
public:
    explicit MyStation(Engine* engine);

    void processEvent(StationEvent event) override;

    // Abort whatever we're keying. Marks the current send as
    // "Garbage" so DX stations interpret the partial transmission as
    // unintelligible rather than as a usable phrase.
    void abortSend();

    // Override to split incoming templates around `<his>` and queue
    // the pieces. Each piece becomes a separate small render so the
    // intervening pieces can change hisCall mid-keying.
    void sendText(const std::string& text) override;

    // Called from getBlock when the current piece's envelope is fully
    // consumed — pops the head piece and starts the next, if any.
    std::size_t getBlock(std::span<float> out) override;

    // Try to update the in-flight call. Returns true when the next
    // pending `<his>` slot can adopt the new call (either we haven't
    // started keying it yet, or the keyed prefix still matches and we
    // can swap the envelope). Pascal: TMyStation.UpdateCallInMessage.
    bool updateCallInMessage(const std::string& newCall);

    // Phase-C diagnostic accessor; remove once Contest's tickAndSweep
    // is verified.
    [[nodiscard]] std::size_t pieceCount() const noexcept { return pieces_.size(); }

private:
    void sendNextPiece();

    // FIFO of pending pieces. "@" is the sentinel for "his callsign"
    // — at render time it expands to the current `hisCall()`.
    std::deque<std::string> pieces_;
};

}  // namespace mr::sim
