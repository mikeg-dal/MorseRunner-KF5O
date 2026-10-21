// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/MyStation.h"

#include "core/Constants.h"
#include "core/Random.h"
#include "dsp/MorseTable.h"
#include "simulation/Engine.h"

#include <string>
#include <string_view>

namespace mr::sim {

namespace {

constexpr std::string_view kHisCallToken = "<his>";
constexpr char kHisCallSentinel = '@';

}  // namespace

MyStation::MyStation(Engine* engine) : Station(engine) {
    // Pascal: TMyStation.Init — sane defaults; Contest writes the real
    // values from Ini on startup.
    setMyCall("VE3NEA");
    setNr(1);
    setRst(599);
    setPitchHz(600);
    setWpm(30);
    setAmplitude(300000.0F);
}

void MyStation::processEvent(StationEvent event) {
    // Pascal: if AEvent = evMsgSent then Tst.OnMeFinishedSending.
    if (event == StationEvent::MsgSent && engine_ != nullptr) {
        engine_->onPlayerFinishedSending();
    }
}

void MyStation::abortSend() {
    envelope_.clear();
    sendPos_ = 0;
    msg_.reset();
    msg_.set(static_cast<std::size_t>(Message::Garbage));
    accumulatedText_.clear();
    pieces_.clear();
    state_ = StationState::Listening;
    processEvent(StationEvent::MsgSent);
}

void MyStation::sendText(const std::string& text) {
    // Split `text` into pieces, every `<his>` becomes an `@` sentinel
    // that we expand at render time using the current hisCall_. This
    // lets the caller change hisCall_ mid-transmission and have it
    // take effect on the next piece.
    std::string remaining(text);

    std::size_t pos = 0;
    while ((pos = remaining.find(kHisCallToken)) != std::string::npos) {
        if (pos > 0) {
            pieces_.push_back(remaining.substr(0, pos));
        }
        pieces_.push_back(std::string(1, kHisCallSentinel));
        remaining.erase(0, pos + kHisCallToken.size());
    }
    if (!remaining.empty()) {
        pieces_.push_back(remaining);
    }

    if (state_ != StationState::Sending) {
        sendNextPiece();
        // Pascal: Tst.OnMeStartedSending.
        if (engine_ != nullptr) {
            engine_->onPlayerStartedSending();
        }
    }
}

void MyStation::sendNextPiece() {
    if (pieces_.empty()) {
        return;
    }

    // Important: clear the accumulated text from any previous piece so
    // the keyer renders just THIS piece. Pascal: MsgText := ''.
    accumulatedText_.clear();

    const std::string& head = pieces_.front();
    if (head.size() == 1 && head[0] == kHisCallSentinel) {
        // Expand the `<his>` slot with whatever hisCall_ is right now.
        // CallsFromKeyer: an external keyer sends the call, so key a
        // blank instead (Pascal keeps the call in WPX and HST).
        const RunMode mode = (engine_ != nullptr) ? engine_->runMode() : RunMode::PileUp;
        if (engine_ != nullptr && engine_->callsFromKeyer()
            && mode != RunMode::Hst && mode != RunMode::Wpx) {
            Station::sendText(" ");
        } else {
            Station::sendText(hisCall_);
        }
    } else {
        // Substitute the remaining placeholders (`<#>`, `<my>`) via
        // the base Station::sendText, but pre-replace any `<#>` here
        // would already be expanded by base. Just hand off.
        Station::sendText(head);
    }
}

std::size_t MyStation::getBlock(std::span<float> out) {
    const std::size_t written = Station::getBlock(out);
    // When the current piece's envelope is exhausted, pop it and start
    // the next. Pascal: TMyStation.GetBlock pops Pieces[0], calls
    // SendNextPiece, then MainForm.Advance.
    if (envelopeExhausted() && !pieces_.empty()) {
        pieces_.pop_front();
        if (!pieces_.empty()) {
            sendNextPiece();
        }
        if (pieceFinished_) {
            pieceFinished_();
        }
    }
    return written;
}

bool MyStation::updateCallInMessage(const std::string& newCall) {
    // Pascal TMyStation.UpdateCallInMessage.
    if (newCall.empty()) {
        return false;
    }

    // Are we sending the call right now?
    bool ok = !pieces_.empty() && pieces_.front().size() == 1
              && pieces_.front()[0] == kHisCallSentinel;

    // Is the part of the call already keyed the same in the new call?
    if (ok) {
        keyer_.setWpm(wpm_);
        auto candidate = keyer_.renderEnvelope(newCall);
        for (float& s : candidate) {
            s *= amplitude_;
        }
        ok = candidate.size() >= sendPos_ && envelope_.size() >= sendPos_;
        for (std::size_t i = 0; ok && i < sendPos_; ++i) {
            ok = (envelope_[i] == candidate[i]);
        }
        if (ok) {
            envelope_ = std::move(candidate);
            setHisCall(newCall);
        }
    }

    // Could not correct the call being keyed, but another call is
    // queued for sending: use the new call there.
    if (!ok) {
        for (std::size_t i = 1; i < pieces_.size(); ++i) {
            if (pieces_[i].size() == 1 && pieces_[i][0] == kHisCallSentinel) {
                setHisCall(newCall);
                return true;
            }
        }
    }
    return ok;
}

}  // namespace mr::sim
