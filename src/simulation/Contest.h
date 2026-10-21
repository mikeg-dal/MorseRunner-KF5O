// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Contest.pas TContest. The simulation orchestrator: owns the
// player station, the audible-source collection, the DSP chain, and
// drives one audio block of mixed output per call to renderNextBlock.
//
// Pascal-equivalent flow for renderNextBlock:
//   1. Allocate a fresh complex (I/Q) noise buffer of bufSize samples.
//   2. Inject QRN spikes (per-sample 1% chance) and QRN-station burst
//      spawns (per-block 1%).
//   3. Spawn QRM stations with 0.0002 per-block probability.
//   4. For each live station, pull its keying envelope chunk and mix
//      into the I/Q buffer with the station's BFO + global RIT phase.
//   5. Apply the player's self-monitor (QSK ducking if enabled).
//   6. Run the ping-pong moving-average LPF over the I/Q buffer.
//   7. Demodulate complex → real via the Modulator at the player's
//      configured pitch.
//   8. Apply the AGC.
//   9. Scale to Float-PCM range (±1.0) and write to `out`.
//  10. tick() every station, sweep finished ones, fire the
//      end-of-session callback when the contest duration elapses.
//
// Threading: lives entirely on the sim thread. Audio thread reads its
// output via the SPSC ring buffer in Audio::SimulationWorker.

#pragma once

#include "core/WavWriter.h"
#include "dsp/Agc.h"
#include "dsp/ComplexBuf.h"
#include "dsp/Modulator.h"
#include "dsp/PingPongFilter.h"
#include "simulation/CallsignSource.h"
#include "simulation/Engine.h"
#include "simulation/Messages.h"
#include "simulation/MyStation.h"
#include "simulation/StationCollection.h"

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <span>

namespace mr::sim {

// Snapshot of the user-facing knobs Contest cares about per render.
// Field names mirror the Pascal Ini globals so the cross-reference
// stays obvious. Settings persistence (Group E) replaces the
// constructor-time defaults with the user's plist.
struct ContestSettings {
    std::string myCallsign = "VE3NEA";
    int wpm = 30;
    int pitchHz = 600;
    int rxBandwidthHz = 500;
    int ritHz = 0;
    bool qsk = true;
    bool qrn = true;
    bool qrm = true;
    bool qsb = true;
    bool flutter = true;
    bool lids = true;
    int activity = 3;
    int durationMinutes = 30;
    float selfMonGain01 = 0.75F;  // VolumeSlider1.Value
    bool callsFromKeyer = false;  // Ini.CallsFromKeyer (INI-only)
    RunMode mode = RunMode::PileUp;
};

class Contest : public Engine {
public:
    explicit Contest(std::unique_ptr<CallsignSource> calls,
                     int bufferSize, mr::core::Random& rng);

    // Engine interface ──────────────────────────────────────────────
    [[nodiscard]] int currentBlockIndex() const noexcept override { return blockIndex_; }
    [[nodiscard]] float currentMinute() const noexcept override { return currentMinute_; }
    [[nodiscard]] std::string_view myCallsign() const override { return settings_.myCallsign; }
    [[nodiscard]] std::string_view heardCallsign() const override { return me_->hisCall(); }
    [[nodiscard]] bool playerSending() const noexcept override {
        return me_->state() == StationState::Sending;
    }
    [[nodiscard]] bool callsFromKeyer() const noexcept override {
        return settings_.callsFromKeyer;
    }
    void onPlayerStartedSending() override { onMeStartedSending(); }
    void onPlayerFinishedSending() override { onMeFinishedSending(); }
    // Reads directly from MyStation's `msg_` bitset so the timing
    // matches Pascal exactly: the message-set resets when MyStation
    // starts a fresh transmission from idle.
    [[nodiscard]] const MessageSet& myLastMessage() const override { return me_->msg(); }
    [[nodiscard]] RunMode runMode() const noexcept override { return settings_.mode; }
    [[nodiscard]] bool lidsEnabled() const noexcept override { return settings_.lids; }
    [[nodiscard]] bool flutterEnabled() const noexcept override { return settings_.flutter; }
    [[nodiscard]] bool qsbEnabled() const noexcept override { return settings_.qsb; }
    [[nodiscard]] int targetWpm() const noexcept override { return settings_.wpm; }
    [[nodiscard]] int activity() const noexcept override { return settings_.activity; }
    [[nodiscard]] int bufferSize() const noexcept override { return bufferSize_; }
    [[nodiscard]] mr::core::Random& random() override { return rng_; }

    // Settings access — applied on the next render. Phase-E pipe will
    // route GUI changes through here via a SettingsSnapshot publish.
    void setSettings(const ContestSettings& s);
    [[nodiscard]] const ContestSettings& settings() const noexcept { return settings_; }

    void setRunMode(RunMode mode);

    // ── Player input (Pascal MainForm → Tst.Me) ────────────────────
    // Pascal TMainForm.SendMsg: for msgHisCall the Call field's text
    // becomes Me.HisCall (if not empty), then Me.SendMsg(msg).
    void playerSendMessage(Message msg, const std::string& callField = {});
    // Pascal TMainForm.Edit1Change → Tst.Me.UpdateCallInMessage. Returns
    // false when the edit could not be applied to a call being keyed or
    // queued (the GUI then clears its CallSent flag).
    bool playerEditedCall(const std::string& callField);
    // Pascal Log.SaveQso's side effects on the simulation: find a
    // finished DX station with this call (DataToLastQso) and bump the
    // player's serial number. `call` is the logged call, '?' stripped.
    void qsoLogged(const std::string& call);
    // Me.Msg flags the GUI needs when Esc aborts a send (Pascal checks
    // msgHisCall / msgNR in Tst.Me.Msg to clear CallSent / NrSent).
    struct AbortInfo { bool hadHisCall; bool hadNr; };
    AbortInfo playerAbortSend();

    // Pascal File → Audio Recording Enabled. While a writer is open
    // every rendered block is appended; turning it off closes and
    // patches the RIFF header. Called from the sim thread only —
    // SimulationWorker marshals the GUI toggle into a queued slot.
    void enableAudioRecording(const std::string& path);
    void disableAudioRecording();

    // Render one audio block. `out` length must be >= bufferSize.
    // Returns the number of samples written (always == bufferSize for
    // a primed Contest; less only at startup while skipping blocks).
    std::size_t renderNextBlock(std::span<float> out);

    // Fired when the configured duration elapses or a requested stop
    // takes effect at the end of a block (Pascal FStopPressed). The GUI
    // picks the end-of-contest popup from the mode and whether the user
    // pressed Stop.
    using EndOfSessionFn = std::function<void(RunMode, bool stoppedByUser)>;
    void setEndOfSessionCallback(EndOfSessionFn cb) {
        endOfSession_ = std::move(cb);
    }
    void requestStop() { stopRequested_ = true; }

    // Fired when a finished DX station matches the last logged QSO
    // (Pascal DataToLastQso). Carries the DX's own record — the truth
    // the GUI's log checks the player's entry against. Runs on the sim
    // thread; receivers marshal to the GUI with a queued signal.
    struct CompletedQso {
        std::string call;
        int rst;
        int nr;
        float minute;   // contest time
    };
    using QsoCompletedFn = std::function<void(const CompletedQso&)>;
    void setQsoCompletedCallback(QsoCompletedFn cb) {
        qsoCompleted_ = std::move(cb);
    }

    // Pascal MainForm.Advance trigger: a piece of the player's message
    // finished keying. Runs on the sim thread.
    void setPlayerPieceFinishedCallback(std::function<void()> cb) {
        me_->setPieceFinishedCallback(std::move(cb));
    }

    [[nodiscard]] MyStation& player() noexcept { return *me_; }
    [[nodiscard]] StationCollection& stations() noexcept { return stations_; }

private:
    void configureDspChain();
    void mixStationsIntoComplex();
    void applySelfMonitor();
    void applyEndOfSession();
    void spawnAutoCallers();
    void tickAndSweep();
    // Report + release finished DX stations whose call matches the last
    // logged QSO. Pascal does this in SaveQso and every block.
    void matchLoggedQso();
    // Pascal: TContest.OnMeFinishedSending. Broadcasts evMeFinished
    // to every station and Poisson-spawns additional callers when the
    // player just sent CQ (or finished a QSO with TU + MyCall).
    void onMeFinishedSending();
    // Pascal: TContest.OnMeStartedSending. Stations in stCopying or
    // stListening notice the player started keying again.
    void onMeStartedSending();

    int bufferSize_;
    mr::core::Random& rng_;

    std::unique_ptr<CallsignSource> callsignSource_;
    std::unique_ptr<MyStation> me_;
    StationCollection stations_;

    mr::dsp::PingPongFilter filter_;
    mr::dsp::Modulator modulator_;
    mr::dsp::Agc agc_;

    mr::dsp::ComplexBuf scratch_;
    std::vector<float> realScratch_;

    ContestSettings settings_;
    // Call of the most recent logged QSO this run (Pascal
    // QsoList[High(QsoList)].Call) and how many QSOs are logged.
    std::string lastLoggedCall_;
    int qsoCount_ = 0;

    int blockIndex_ = 0;
    float currentMinute_ = 0.0F;
    double ritPhase_ = 0.0;
    float qskRfg_ = 1.0F;


    bool stopRequested_ = false;
    bool ended_ = false;
    EndOfSessionFn endOfSession_;
    QsoCompletedFn qsoCompleted_;

    // Optional Pascal "Save WAV" output. unique_ptr to keep the
    // ofstream-bearing WavWriter out of every Contest.h includer when
    // recording is off (which is the default).
    std::unique_ptr<mr::core::WavWriter> wavWriter_;
};

}  // namespace mr::sim
