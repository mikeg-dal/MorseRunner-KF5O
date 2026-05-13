// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Station.pas TStation. Abstract base for every audible source
// in the simulation — the player (MyStation), DX callers (DxStation),
// and the interferer stations (QrnStation / QrmStation).
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

#pragma once

#include "dsp/MorseKeyer.h"
#include "simulation/Messages.h"

#include <cstddef>
#include <cstdint>
#include <limits>
#include <span>
#include <string>
#include <vector>

namespace mr::sim {

class Engine;

enum class StationState {
    Listening,
    Copying,
    PreparingToSend,
    Sending,
};

enum class StationEvent {
    Timeout,
    MsgSent,
    MeStarted,
    MeFinished,
};

// Sentinel "never trigger a timeout" value. Stored as a regular int so
// it round-trips through subtraction cleanly without overflow as long
// as nobody adds to it.
inline constexpr int kNeverTimeout = std::numeric_limits<int>::max();

class Station {
public:
    explicit Station(Engine* engine);
    virtual ~Station() = default;

    Station(const Station&) = delete;
    Station& operator=(const Station&) = delete;
    Station(Station&&) = delete;
    Station& operator=(Station&&) = delete;

    // Subclasses dispatch on event kind. Contest calls this once per
    // event from its render loop.
    virtual void processEvent(StationEvent event) = 0;

    // Per-block timer tick. If TimeOut hits 0 (and not Sending) we
    // fire processEvent(Timeout). If the envelope has been fully
    // consumed while Sending, we transition to Listening and fire
    // processEvent(MsgSent).
    void tick();

    // Pulls up to `bufSize` samples from the envelope into `out`. Any
    // samples beyond the envelope's length are left as 0 (Contest does
    // not allocate per-block — the destination is a member of an
    // AudioFrame or scratch buffer that was already zero-initialized).
    // Returns the number of samples actually written from the envelope
    // (0 when not Sending).
    virtual std::size_t getBlock(std::span<float> out);

    // Queue an outgoing message. Substitutes placeholders and renders
    // the envelope via the MorseKeyer; subsequent getBlock() calls
    // pull from that envelope. The state transitions to Sending.
    virtual void sendMsg(Message msg);
    virtual void sendText(const std::string& text);

    // Accessors used by Contest mixing.
    [[nodiscard]] StationState state() const noexcept { return state_; }
    [[nodiscard]] const MessageSet& msg() const noexcept { return msg_; }
    [[nodiscard]] double bfoPhase() const noexcept { return bfoPhase_; }
    [[nodiscard]] float amplitude() const noexcept { return amplitude_; }
    [[nodiscard]] int wpm() const noexcept { return wpm_; }

    // Set the BFO offset in Hz. Updates the per-sample phase advance
    // immediately (the next sample's BFO will be at the new rate).
    void setPitchHz(int pitchHz);
    [[nodiscard]] int pitchHz() const noexcept { return pitchHz_; }

    void setWpm(int wpm) {
        wpm_ = wpm;
        keyer_.setWpm(wpm);
    }
    void setMyCall(std::string call) { myCall_ = std::move(call); }
    void setHisCall(std::string call) { hisCall_ = std::move(call); }
    void setRst(int rst) noexcept { rst_ = rst; }
    void setNr(int nr) noexcept { nr_ = nr; }
    void setAmplitude(float a) noexcept { amplitude_ = a; }

    [[nodiscard]] const std::string& myCall() const noexcept { return myCall_; }
    [[nodiscard]] const std::string& hisCall() const noexcept { return hisCall_; }
    [[nodiscard]] int rst() const noexcept { return rst_; }
    [[nodiscard]] int nr() const noexcept { return nr_; }

    // Advances the BFO phase one sample. Called by the Contest's
    // mixing loop after each sample is consumed; we expose it as a
    // method (rather than a per-sample increment baked into getBlock)
    // because the mixer needs both the *current* phase for sin/cos AND
    // independent control over advancing it.
    [[nodiscard]] double tickBfoPhase() noexcept;

    void setTimeout(int blocks) noexcept { timeout_ = blocks; }
    [[nodiscard]] int timeout() const noexcept { return timeout_; }
    [[nodiscard]] bool envelopeExhausted() const noexcept {
        return sendPos_ >= envelope_.size();
    }

protected:
    // Builds the NrAsText string for substituting `<#>` in templates.
    // Pulled out so subclasses (LID DxStations) can pre-flag errors.
    [[nodiscard]] std::string nrAsText(bool injectLidError);

    // Subclasses may override to customize text rewriting (e.g.
    // MyStation splits around `<his>` for mid-keying call correction).
    virtual void sendMorse(const std::string& morse);

    Engine* engine_;
    mr::dsp::MorseKeyer keyer_;
    std::vector<float> envelope_;
    std::size_t sendPos_ = 0;
    std::string accumulatedText_;
    int timeout_ = kNeverTimeout;

    MessageSet msg_{};
    StationState state_ = StationState::Listening;

    std::string myCall_;
    std::string hisCall_;
    int rst_ = 599;
    int nr_ = 1;
    int wpm_ = 30;
    int pitchHz_ = 600;
    bool nrWithError_ = false;
    float amplitude_ = 1.0F;

    // BFO phase accumulator. We use double here because the per-sample
    // delta is small (a few µrad) and float accumulates audible drift
    // over multi-second runs.
    double bfoPhase_ = 0.0;
    double bfoPhaseDelta_ = 0.0;

private:
    void recomputeBfoDelta();
};

}  // namespace mr::sim
