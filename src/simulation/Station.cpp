// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/Station.h"

#include "core/Constants.h"
#include "core/Logging.h"
#include "core/Random.h"
#include "dsp/MorseTable.h"
#include "simulation/Engine.h"
#include "simulation/NumberFormat.h"

#include <QString>

#include <algorithm>
#include <string>
#include <string_view>

namespace mr::sim {

namespace {

// Replace every occurrence of `from` in `s` with `to`. Pascal:
// StringReplace(..., [rfReplaceAll]).
void replaceAll(std::string& s, std::string_view from, std::string_view to) {
    if (from.empty()) {
        return;
    }
    std::size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
        pos += to.size();
    }
}

}  // namespace

Station::Station(Engine* engine)
    : engine_(engine),
      keyer_(mr::constants::Audio::kSampleRate, 30) {
    recomputeBfoDelta();
}

void Station::setPitchHz(int pitchHz) {
    pitchHz_ = pitchHz;
    recomputeBfoDelta();
}

void Station::recomputeBfoDelta() {
    using mr::constants::Math::kTwoPi;
    bfoPhaseDelta_ = kTwoPi * static_cast<double>(pitchHz_)
                     / static_cast<double>(mr::constants::Audio::kSampleRate);
}

double Station::tickBfoPhase() noexcept {
    using mr::constants::Math::kTwoPi;
    const double result = bfoPhase_;
    bfoPhase_ += bfoPhaseDelta_;
    if (bfoPhase_ > kTwoPi) {
        bfoPhase_ -= kTwoPi;
    }
    return result;
}

std::size_t Station::getBlock(std::span<float> out) {
    if (state_ != StationState::Sending || envelope_.empty()) {
        return 0;
    }
    const std::size_t remaining =
        (sendPos_ < envelope_.size()) ? (envelope_.size() - sendPos_) : 0;
    const std::size_t copied = std::min(remaining, out.size());
    if (copied > 0) {
        const auto begin = envelope_.begin() + static_cast<std::ptrdiff_t>(sendPos_);
        std::copy(begin, begin + static_cast<std::ptrdiff_t>(copied), out.begin());
        sendPos_ += copied;
    }
    if (sendPos_ >= envelope_.size()) {
        // Envelope fully consumed; Contest will see this via
        // envelopeExhausted() and tick() will fire the MsgSent event
        // on the next tick.
        envelope_.clear();
        sendPos_ = 0;
    }
    return copied;
}

void Station::sendMsg(Message m) {
    // Pascal: if Envelope = nil then Msg := [] — i.e., wipe the message
    // set whenever we start a new transmission from idle.
    if (envelope_.empty()) {
        msg_.reset();
    }
    if (m == Message::None) {
        state_ = StationState::Listening;
        return;
    }
    msg_.set(static_cast<std::size_t>(m));

    std::string_view tmpl = templateFor(m);
    if (!tmpl.empty()) {
        sendText(std::string(tmpl));
    }
}

void Station::sendText(const std::string& text) {
    using mr::constants::Math::kTwoPi;

    // Pascal TStation.SendText:
    //   AMsg := StringReplace(AMsg, '<#>', NrAsText, []);              // first, may carry the LID error
    //   AMsg := StringReplace(AMsg, '<#>', NrAsText, [rfReplaceAll]);  // the rest, one fresh value
    // so in "R <#> <#>" (R_NR2) only the first copy has the error and
    // each copy rolls its own cut-number style.
    std::string assembled(text);
    if (const auto first = assembled.find("<#>"); first != std::string::npos) {
        assembled.replace(first, 3, nrAsText(nrWithError_));
        if (assembled.find("<#>") != std::string::npos) {
            replaceAll(assembled, "<#>", nrAsText(false));
        }
    }

    // `<my>` is the SENDING station's call (always own).
    replaceAll(assembled, "<my>", myCall_);
    // Pascal's base SendText leaves `<his>` in place (its substitution is
    // commented out) and the keyer has no code for '<', 'h', 'i', 's' or
    // '>', so it keys as nothing: QRM's "<his>  QSY QSY" is heard as
    // "QSY QSY". MyStation splits around `<his>` itself and never gets
    // here with the token.
    replaceAll(assembled, "<his>", "");

    if (accumulatedText_.empty()) {
        accumulatedText_ = assembled;
    } else {
        accumulatedText_ += ' ';
        accumulatedText_ += assembled;
    }
    sendMorse(mr::dsp::encodeMessage(accumulatedText_));
}

void Station::sendMorse(const std::string& morse) {
    // Reset the cursor and BFO if we're starting from idle (matches
    // Pascal: `if Envelope = nil then begin SendPos := 0; FBfo := 0`).
    if (envelope_.empty()) {
        sendPos_ = 0;
        bfoPhase_ = 0.0;
    }

    keyer_.setWpm(wpm_);
    envelope_ = keyer_.renderEnvelope(morse);
    for (float& s : envelope_) {
        s *= amplitude_;
    }
    state_ = StationState::Sending;
    timeout_ = kNeverTimeout;
}

void Station::tick() {
    // Pascal Station.pas::Tick:
    //   - If state was Sending and Envelope is gone, transition to
    //     Listening and fire MsgSent.
    //   - Else if not Sending, decrement the TimeOut and fire Timeout
    //     when it crosses zero.
    if (state_ == StationState::Sending && envelope_.empty()) {
        accumulatedText_.clear();
        state_ = StationState::Listening;
        processEvent(StationEvent::MsgSent);
    } else if (state_ != StationState::Sending) {
        if (timeout_ > -1 && timeout_ != kNeverTimeout) {
            --timeout_;
        }
        if (timeout_ == 0) {
            processEvent(StationEvent::Timeout);
        }
    }
}

std::string Station::nrAsText(bool injectLidError) {
    NrFormatOptions opts;
    opts.rst = rst_;
    opts.nr = nr_;
    opts.hstMode = (engine_ != nullptr && engine_->runMode() == RunMode::Hst);
    opts.lidError = injectLidError;
    nrWithError_ = false;  // consume the flag
    if (engine_ != nullptr) {
        return mr::sim::nrAsText(opts, engine_->random());
    }
    // Engine-less path is exercised by tests that construct a station
    // directly without a Contest. Pull from the singleton.
    return mr::sim::nrAsText(opts, mr::core::Random::instance());
}

}  // namespace mr::sim
