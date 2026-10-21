// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/Contest.h"

#include "core/Constants.h"
#include "core/DelphiRound.h"
#include "core/Logging.h"
#include "core/Random.h"

#include <algorithm>
#include <cmath>

namespace mr::sim {

namespace {

// PCM output scaling: AGC writes ±~kAgcMaxOut, QAudioSink Float wants
// ±1.0. We use 1/32768 (the 16-bit PCM full-scale) so the headroom
// budget matches the original — Pascal output was 16-bit PCM and the
// AGC was tuned around that scale.
constexpr float kFloatPcmScale = 1.0F / 32768.0F;
constexpr float kAgcMaxOut = 20000.0F;

}  // namespace

Contest::Contest(std::unique_ptr<CallsignSource> calls,
                 int bufferSize, mr::core::Random& rng)
    : bufferSize_(bufferSize),
      rng_(rng),
      callsignSource_(std::move(calls)),
      modulator_(mr::constants::Audio::kSampleRate, 600.0F),
      scratch_() {
    using namespace mr::constants::Dsp;
    me_ = std::make_unique<MyStation>(this);

    // One-time AGC setup. The parameters are constants; mutating them
    // later would reset the AGC delay line and cause an audible click.
    agc_.setMaxOut(kAgcMaxOut);
    agc_.setNoiseInDb(kAgcNoiseInDb);
    agc_.setNoiseOutDb(kAgcNoiseOutDb);
    agc_.setAttackSamples(kAgcAttackSamples);
    agc_.setHoldSamples(kAgcHoldSamples);
    agc_.setEnabled(true);

    scratch_.resize(static_cast<std::size_t>(bufferSize_));
    realScratch_.assign(static_cast<std::size_t>(bufferSize_), 0.0F);

    // setSettings applies the defaults stored in settings_ (including
    // bandwidth → filter config) using the diff-aware path. The
    // previous-settings comparison sees uninitialized values so
    // everything triggers exactly once. We then call configureDspChain
    // explicitly because the initial diff has no "previous" state.
    configureDspChain();
    me_->setMyCall(settings_.myCallsign);
    me_->setWpm(settings_.wpm);
    me_->setPitchHz(settings_.pitchHz);
    modulator_.setCarrierFreq(static_cast<float>(settings_.pitchHz));
}

void Contest::setSettings(const ContestSettings& s) {
    // Diff-aware update. The naive "rebuild everything on every
    // change" approach caused audible clicks/stutter every time the
    // user touched a control (RIT drag, WPM spin, etc.) because the
    // moving-average filter resets its delay line on configure() and
    // the modulator resets its phase index on setCarrierFreq(). Now
    // we only touch DSP state when the value that drives it changed.
    const auto prev = settings_;
    settings_ = s;

    if (me_ && (prev.myCallsign != s.myCallsign)) {
        me_->setMyCall(s.myCallsign);
    }
    if (me_ && (prev.wpm != s.wpm)) {
        me_->setWpm(s.wpm);
    }
    if (me_ && (prev.pitchHz != s.pitchHz)) {
        me_->setPitchHz(s.pitchHz);
    }
    if (prev.pitchHz != s.pitchHz) {
        modulator_.setCarrierFreq(static_cast<float>(s.pitchHz));
    }
    if (prev.rxBandwidthHz != s.rxBandwidthHz) {
        configureDspChain();
    }
}

void Contest::setRunMode(RunMode mode) {
    settings_.mode = mode;
    ended_ = false;
    stopRequested_ = false;

    if (mode == RunMode::Stop) {
        // Pascal Run(rmStop) only disables audio output, so the clock
        // keeps showing the final contest time. The station list is
        // cleared here (Pascal clears it at the next Run) so nothing
        // keyed while stopped piles up.
        me_->abortSend();
        stations_.clear();
        return;
    }

    // Pascal Run(<mode>): Tst.Me.AbortSend; Tst.BlockNumber := 0;
    // Tst.Me.Nr := 1; Log.Clear (which also clears Tst.Stations).
    // Starting a run keys nothing: in Pile-Up / WPX the player sends a
    // CQ to draw callers; Single / HST callers come from
    // spawnAutoCallers.
    me_->abortSend();
    blockIndex_ = 0;
    currentMinute_ = 0.0F;
    me_->setNr(1);
    stations_.clear();
    lastLoggedCall_.clear();
    qsoCount_ = 0;
}

namespace {

std::string upper(std::string s) {
    // IsMyCall compares raw characters, so keep calls upper-case the way
    // Pascal's ecUpperCase edit does.
    for (char& c : s) {
        if (c >= 'a' && c <= 'z') {
            c = static_cast<char>(c - 'a' + 'A');
        }
    }
    return s;
}

}  // namespace

void Contest::playerSendMessage(Message msg, const std::string& callField) {
    // Pascal TMainForm.SendMsg.
    if (msg == Message::HisCall && !callField.empty()) {
        me_->setHisCall(upper(callField));
    }
    me_->sendMsg(msg);
}

bool Contest::playerEditedCall(const std::string& callField) {
    return me_->updateCallInMessage(upper(callField));
}

void Contest::qsoLogged(const std::string& call) {
    // Pascal Log.SaveQso: look for the DX station in the log, then
    // Inc(Tst.Me.NR).
    lastLoggedCall_ = upper(call);
    ++qsoCount_;
    matchLoggedQso();
    me_->setNr(me_->nr() + 1);
}

Contest::AbortInfo Contest::playerAbortSend() {
    const MessageSet& m = me_->msg();
    const AbortInfo info{contains(m, Message::HisCall), contains(m, Message::Nr)};
    me_->abortSend();
    return info;
}

void Contest::matchLoggedQso() {
    if (lastLoggedCall_.empty()) {
        return;
    }
    for (auto& sptr : stations_) {
        auto* dx = dynamic_cast<DxStation*>(sptr.get());
        if (dx == nullptr || dx->shouldRemove()
            || dx->operatorState().state() != OperatorState::Done
            || dx->myCall() != lastLoggedCall_) {
            continue;
        }
        // TDxStation.DataToLastQso, then Free.
        if (qsoCompleted_) {
            CompletedQso q;
            q.call = dx->myCall();
            q.rst = dx->rst();
            q.nr = dx->nr();
            q.minute = currentMinute_;
            qsoCompleted_(q);
        }
        dx->release();
    }
}

void Contest::enableAudioRecording(const std::string& path) {
    if (!wavWriter_) {
        wavWriter_ = std::make_unique<mr::core::WavWriter>();
    }
    if (!wavWriter_->open(path)) {
        wavWriter_.reset();
    }
}

void Contest::disableAudioRecording() {
    if (wavWriter_) {
        wavWriter_->close();
        wavWriter_.reset();
    }
}

void Contest::configureDspChain() {
    using namespace mr::constants::Dsp;
    // Filter coefficients depend on the user-selectable bandwidth.
    // Pascal: Filt.Points = round(0.7 * SR / BW); Passes = 3;
    // GainDb = 10*log10(500/BW). This function is also called from
    // setSettings when bandwidth changes — it resets the filter's
    // delay line, which is what we want when bandwidth shifts.
    const float bw = std::max(1.0F, static_cast<float>(settings_.rxBandwidthHz));
    const int points = std::max(1,
        mr::core::delphiRound(
            kFilterPointsRatio * static_cast<float>(mr::constants::Audio::kSampleRate)
            / bw));
    const float gainDb = 10.0F * std::log10(kFilterGainRefBw / bw);
    filter_.configure(points, kFilterPasses, bufferSize_, gainDb);

    // NOTE: AGC parameters are constants and never change after the
    // initial setup in the Contest constructor. They used to be
    // re-applied here too, which silently reset the AGC delay line
    // on every settings change and caused audible clicks.
}

void Contest::onMeFinishedSending() {
    // Pascal: TContest.OnMeFinishedSending.
    using namespace mr::constants::Sim;
    const MessageSet& heard = me_->msg();
    const bool playerCq = contains(heard, Message::Cq);
    // 1.68: TU + MyCall after a QSO counts as a CQ (QsoList <> nil).
    const bool playerEndedQso = qsoCount_ > 0
        && contains(heard, Message::Tu) && contains(heard, Message::MyCall);
    const bool spawnEligible = (settings_.mode != RunMode::Single)
                               && (settings_.mode != RunMode::Hst);
    int spawnCount = 0;
    if (spawnEligible && (playerCq || playerEndedQso)) {
        // Pascal: for i := 1 to RndPoisson(Activity / 2) do
        // Stations.AddCaller. Average ~1-3 new callers per CQ at
        // default activity = 3.
        const float lambda = static_cast<float>(settings_.activity)
                             / kCallerSpawnRateActivityDivisor;
        spawnCount = rng_.poisson(lambda);
        for (int i = 0; i < spawnCount; ++i) {
            stations_.addCaller(this, callsignSource_->pickCall(rng_));
        }
    }
    qCDebug(mrSim) << "me finished: cq=" << playerCq << "endedQso=" << playerEndedQso
                  << "spawned=" << spawnCount << "dxOnBand=" << stations_.dxCount()
                  << "activity=" << settings_.activity;
    // Broadcast evMeFinished to every station so DxOperators in
    // stCopying interpret the message-set we just keyed.
    for (auto& s : stations_) {
        s->processEvent(StationEvent::MeFinished);
    }

}

void Contest::onMeStartedSending() {
    for (auto& s : stations_) {
        s->processEvent(StationEvent::MeStarted);
    }
}

void Contest::mixStationsIntoComplex() {
    // Pascal: for each station in stSending state, pull bufSize
    // samples and mix into the I/Q buffer with that station's BFO
    // plus the global RIT phase. The BFO phase is *not* tickBfoPhase()
    // (a station-internal accumulator) — Pascal grabs Station.Bfo once
    // per block then walks linearly. We mirror that by snapshotting
    // the station's phase at i=0 and advancing locally.
    using mr::constants::Math::kTwoPi;
    const double ritRadPerSample = kTwoPi * static_cast<double>(settings_.ritHz)
                                   / static_cast<double>(mr::constants::Audio::kSampleRate);

    for (auto& sptr : stations_) {
        Station* s = sptr.get();
        if (s->state() != StationState::Sending) {
            continue;
        }
        // Pull samples into a scratch real-only buffer; ignore the
        // unmodulated samples Station::getBlock wrote — they're the
        // base envelope. We need to apply the BFO ourselves so we can
        // mix into I/Q simultaneously.
        std::fill(realScratch_.begin(), realScratch_.end(), 0.0F);
        const std::size_t got = s->getBlock(realScratch_);
        if (got == 0) {
            continue;
        }
        // Sample the BFO once per block; the per-sample increment is
        // already known via Station's internal delta (re-derived
        // from pitchHz).
        const double bfoStart = s->bfoPhase();
        // Pascal walks `i = 0..High(Blk)` and computes:
        //   Bfo = Station.Bfo - RitPhase - i * 2π * RIT / SR
        // The `Station.Bfo` getter advances by dPhi each call, so over
        // the block it ends at (start + bufSize·dPhi). We replicate that
        // by manually iterating both the pitch phase and the RIT phase.
        const double pitchRadPerSample =
            kTwoPi * static_cast<double>(s->pitchHz())
            / static_cast<double>(mr::constants::Audio::kSampleRate);
        double phase = bfoStart;
        const double ritStart = ritPhase_;
        for (std::size_t i = 0; i < got; ++i) {
            const double bfo = phase - ritStart - static_cast<double>(i) * ritRadPerSample;
            const float sample = realScratch_[i];
            scratch_.re[i] += static_cast<float>(sample * std::cos(bfo));
            scratch_.im[i] -= static_cast<float>(sample * std::sin(bfo));
            phase += pitchRadPerSample;
        }
        // Synchronize the station's internal BFO with where we
        // computationally walked it. Cheap: tick the accumulator
        // `got` times to keep state consistent for the next call.
        for (std::size_t i = 0; i < got; ++i) {
            (void) s->tickBfoPhase();
        }
    }

    // Advance the RIT phase accumulator for the next block.
    ritPhase_ += static_cast<double>(bufferSize_) * ritRadPerSample;
    while (ritPhase_ > kTwoPi) {
        ritPhase_ -= kTwoPi;
    }
    while (ritPhase_ < -kTwoPi) {
        ritPhase_ += kTwoPi;
    }
}

void Contest::applySelfMonitor() {
    using namespace mr::constants::Dsp;
    if (me_->state() != StationState::Sending) {
        return;
    }
    std::fill(realScratch_.begin(), realScratch_.end(), 0.0F);
    const std::size_t got = me_->getBlock(realScratch_);
    if (got == 0) {
        return;
    }
    // Smg = 10^((slider - 0.75) * 4). Pascal: Contest.pas::GetAudio.
    const float smg =
        std::pow(10.0F, (settings_.selfMonGain01 - kSelfMonGainSliderZero) * kSelfMonGainScale);
    const float amp = me_->amplitude();

    if (settings_.qsk) {
        // QSK: duck the external signal proportional to our own
        // transmission envelope. Pascal:
        //   if Rfg > (1 - blk/amp) then Rfg := 1 - blk/amp
        //   else Rfg := Rfg*0.997 + 0.003
        //   Re/Im[i] = Smg*blk + Rfg*Re/Im[i]
        for (std::size_t i = 0; i < got; ++i) {
            const float blk = realScratch_[i];
            const float target = 1.0F - blk / amp;
            if (qskRfg_ > target) {
                qskRfg_ = target;
            } else {
                qskRfg_ = qskRfg_ * kQskAttackCoeff + kQskReleaseAdd;
            }
            scratch_.re[i] = smg * blk + qskRfg_ * scratch_.re[i];
            scratch_.im[i] = smg * blk + qskRfg_ * scratch_.im[i];
        }
    } else {
        // Non-QSK: clobber external signal entirely while keying
        // (the operator can't hear band noise during their own send).
        for (std::size_t i = 0; i < got; ++i) {
            scratch_.re[i] = smg * realScratch_[i];
            scratch_.im[i] = smg * realScratch_[i];
        }
    }
}

void Contest::applyEndOfSession() {
    if (ended_) {
        return;
    }
    const float durationSec = static_cast<float>(settings_.durationMinutes) * 60.0F;
    const float elapsed = static_cast<float>(
        mr::constants::Audio::blocksToSeconds(static_cast<double>(blockIndex_), bufferSize_));
    if (elapsed >= durationSec || stopRequested_) {
        ended_ = true;
        const RunMode mode = settings_.mode;
        const bool byUser = stopRequested_;
        setRunMode(RunMode::Stop);
        if (endOfSession_) {
            endOfSession_(mode, byUser);
        }
    }
}

void Contest::spawnAutoCallers() {
    // Pascal Contest.pas::GetAudio tail end:
    //   rmSingle and DxCount=0 → spawn one caller
    //   rmHst and DxCount<Activity → top up to Activity
    // In both cases Pascal first sets `Me.Msg := [msgCQ]` and then hands
    // each new caller an evMeFinished, so it behaves as if it just heard
    // a CQ (NeedPrevEnd → NeedQso) and calls after its send delay.
    // Without the event the caller would sit in Copying forever and
    // nobody would call until the player transmitted something.
    MessageSet cq{};
    cq.set(static_cast<std::size_t>(Message::Cq));
    if (settings_.mode == RunMode::Single && stations_.dxCount() == 0) {
        me_->setMsg(cq);
        stations_.addCaller(this, callsignSource_->pickCall(rng_))
            ->processEvent(StationEvent::MeFinished);
    } else if (settings_.mode == RunMode::Hst) {
        const int needed = settings_.activity - static_cast<int>(stations_.dxCount());
        if (needed > 0) {
            me_->setMsg(cq);
        }
        for (int i = 0; i < needed; ++i) {
            const std::string call = callsignSource_->pickAndRemoveCall(rng_);
            stations_.addCaller(this, call)->processEvent(StationEvent::MeFinished);
        }
    }
}

void Contest::tickAndSweep() {
    // Pascal GetAudio: Me.Tick, then every station's Tick (last to
    // first). The player's start/finish events fire synchronously from
    // MyStation (sendText / MsgSent), as in Pascal.
    me_->tick();
    for (std::size_t i = stations_.size(); i-- > 0;) {
        stations_[i].tick();
    }

    // "if DX is done, write to log and kill" — the DX matching the last
    // logged QSO hands over its record, then goes away.
    matchLoggedQso();

    stations_.sweep();
}

std::size_t Contest::renderNextBlock(std::span<float> out) {
    using namespace mr::constants::Audio;
    using namespace mr::constants::Dsp;

    if (out.size() < static_cast<std::size_t>(bufferSize_)) {
        return 0;
    }
    if (settings_.mode == RunMode::Stop) {
        std::fill_n(out.begin(), bufferSize_, 0.0F);
        return static_cast<std::size_t>(bufferSize_);
    }

    ++blockIndex_;
    currentMinute_ = static_cast<float>(
        blocksToSeconds(static_cast<double>(blockIndex_), bufferSize_) / 60.0);

    // Pascal: skip first 6 blocks to mask startup pop.
    if (blockIndex_ < kStartupSkipBlocks) {
        std::fill_n(out.begin(), bufferSize_, 0.0F);
        return static_cast<std::size_t>(bufferSize_);
    }

    // 1) Complex Gaussian noise. Pascal: 3 · NOISEAMP · (R - 0.5).
    for (std::size_t i = 0; i < static_cast<std::size_t>(bufferSize_); ++i) {
        scratch_.re[i] = kNoiseChannelGainMul * kNoiseAmp * (rng_.uniform01() - 0.5F);
        scratch_.im[i] = kNoiseChannelGainMul * kNoiseAmp * (rng_.uniform01() - 0.5F);
    }

    // 2) QRN: per-sample spike + per-block burst spawn.
    if (settings_.qrn) {
        for (std::size_t i = 0; i < static_cast<std::size_t>(bufferSize_); ++i) {
            if (rng_.uniform01() < kQrnSpikePerSampleProb) {
                scratch_.re[i] = kQrnSpikeAmpMul * kNoiseAmp * (rng_.uniform01() - 0.5F);
            }
        }
        if (rng_.uniform01() < kQrnBurstPerBlockProb) {
            stations_.addQrn(this);
        }
    }

    // 3) QRM: per-block spawn.
    if (settings_.qrm && rng_.uniform01() < kQrmSpawnPerBlockProb) {
        stations_.addQrm(this, callsignSource_->pickCall(rng_));
    }

    // 4) Mix every active station's keying into the I/Q buffer.
    mixStationsIntoComplex();

    // 5) Player self-monitor (QSK ducks the external signal, or
    //    bypass clobbers it for non-QSK).
    applySelfMonitor();

    // 6) Ping-pong LPF over the complex buffer.
    filter_.process(scratch_);

    // 7) Modulator: complex → real PCM.
    modulator_.modulate(scratch_, std::span<float>(realScratch_.data(),
                                                   static_cast<std::size_t>(bufferSize_)));

    // 8) AGC.
    agc_.process(std::span<float>(realScratch_.data(),
                                  static_cast<std::size_t>(bufferSize_)));

    // 9) Scale to ±1 Float-PCM and copy to caller.
    for (std::size_t i = 0; i < static_cast<std::size_t>(bufferSize_); ++i) {
        out[i] = realScratch_[i] * kFloatPcmScale;
    }

    // 9b) Pascal "Save WAV" tap. The recorded stream is the same
    // final-mixed signal the audio thread plays — sidetone, QSK
    // ducking, AGC, and all band conditions are baked in.
    if (wavWriter_) {
        wavWriter_->append(std::span<const float>(out.data(),
                                                  static_cast<std::size_t>(bufferSize_)));
    }

    // 10) Per-block bookkeeping: tick + sweep, auto-spawn, end check.
    tickAndSweep();
    spawnAutoCallers();
    applyEndOfSession();

    return static_cast<std::size_t>(bufferSize_);
}

}  // namespace mr::sim
