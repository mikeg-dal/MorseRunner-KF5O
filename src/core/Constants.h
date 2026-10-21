// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Central registry for every numeric literal used by the simulator.
//
// The "no magic numbers" rule for this codebase: any constant that
// appears in `src/dsp/`, `src/simulation/`, `src/scoring/`, `src/audio/`,
// `src/persistence/`, or `src/ui/` must be declared here with a brief
// comment naming its Pascal origin. `docs/constants-citations.md` is the
// auditable mapping. Local-only bookkeeping integers (loop counters,
// trivial buffer indices) are exempt.
//
// All groupings live under `mr::constants::<Category>`. Categories:
//   Audio    — sample rate, buffer sizes, startup pacing.
//   Dsp      — filter coefficients, AGC parameters, keying math.
//   Sim      — operator FSM, station spawn parameters, mishearing rates.
//   Scoring  — log formatting widths, CRC32 seed, prefix limits.
//   Ui       — pixel layout, font sizes, GUI throttle.
//   Math     — π and friends, in one place to avoid std::numbers vs
//              <cmath> M_PI vs ad-hoc literals drift.

#pragma once

#include <cstdint>

namespace mr::constants {

// ─── Math ───────────────────────────────────────────────────────────────────
namespace Math {
    inline constexpr double kPi = 3.141592653589793;
    inline constexpr double kTwoPi = 2.0 * kPi;
    inline constexpr double kHalfPi = 0.5 * kPi;
}  // namespace Math

// ─── Audio ──────────────────────────────────────────────────────────────────
namespace Audio {
    // Legacy Windows-Sound-System rate. All filter coefficients, BFO sin/cos
    // tables, and Morse envelope ramps are computed against it; changing it
    // would require re-deriving every dependent constant downstream.
    // Pascal: Ini.pas DEFAULTRATE.
    inline constexpr int kSampleRate = 11025;

    // Buffer size is selected by INI exponent V in [1..5]; samples = 64 << V.
    // V=3 (default) → 512 samples ≈ 46.4 ms — the original's default.
    // Pascal: Ini.pas::FromIni computes `BufSize := 64 shl V`.
    inline constexpr int kBufferExpMin = 1;
    inline constexpr int kBufferExpMax = 5;
    inline constexpr int kBufferExpDefault = 3;
    [[nodiscard]] constexpr int bufferSamplesFor(int exp) noexcept {
        return 64 << exp;
    }
    inline constexpr int kMinBufferSamples = bufferSamplesFor(kBufferExpMin);   // 128
    inline constexpr int kDefaultBufferSamples = bufferSamplesFor(kBufferExpDefault);  // 512
    inline constexpr int kMaxBufferSamples = bufferSamplesFor(kBufferExpMax);   // 2048

    // First 5 audio blocks are discarded to mask the startup pop produced by
    // the moving-average filter settling. Pascal: Contest.pas::GetAudio
    // `if BlockNumber < 6 then Exit`.
    inline constexpr int kStartupSkipBlocks = 6;

    // Ping-pong cadence between Filt and Filt2: every 10 blocks we swap so
    // the now-shadow filter can be Reset without producing a click. Pascal:
    // Contest.pas::GetAudio `if (BlockNumber mod 10) = 0 then SwapFilters`.
    inline constexpr int kFilterSwapBlocks = 10;

    // Audio output ring depth in frames (one frame = one block of
    // 46.4 ms at 512 samples). Was 8 (~371 ms), which meant a fully-
    // pre-rendered ring delayed F-key keystrokes until previously-
    // queued audio drained. 3 frames (~140 ms) keeps plenty of headroom
    // for the 250 Hz renderTick QTimer to outrun the audio thread's
    // 22 Hz consumption rate, while cutting input-to-audio latency by
    // ~2.5×. Underruns at this depth on M1 are still zero in practice.
    inline constexpr int kAudioRingFrames = 3;

    // WAV writer ring: deeper because disk-write hiccups are spikier than
    // audio-callback jitter. ~3 s at default buffer.
    inline constexpr int kWavRingFrames = 64;

    // Helper: convert audio-block index ↔ wall-clock seconds at the
    // default buffer size. Equivalent to the Pascal `BlocksToSeconds` /
    // `SecondsToBlocks` in RndFunc.pas.
    [[nodiscard]] constexpr double blocksToSeconds(double blocks,
                                                   int bufSize = kDefaultBufferSamples) noexcept {
        return blocks * static_cast<double>(bufSize) / static_cast<double>(kSampleRate);
    }
    [[nodiscard]] constexpr int secondsToBlocks(double seconds,
                                                int bufSize = kDefaultBufferSamples) noexcept {
        return static_cast<int>(static_cast<double>(kSampleRate) / static_cast<double>(bufSize)
                                * seconds
                                + 0.5);
    }
}  // namespace Audio

// ─── DSP ────────────────────────────────────────────────────────────────────
namespace Dsp {
    // Noise floor in raw linear PCM units. Sized so the AGC has room above
    // and below it before clip. Pascal: Contest.pas NOISEAMP = 6000.
    inline constexpr float kNoiseAmp = 6000.0f;
    // Complex Gaussian noise injected at 3× NOISEAMP per channel (Re, Im).
    inline constexpr float kNoiseChannelGainMul = 3.0f;

    // QRN spike (per-sample) inside the noise pass: 1% chance, 60× noise.
    // Pascal: Contest.pas::GetAudio `if Random < 0.01 then
    // ReIm.Re[i] := 60 * NOISEAMP * (Random-0.5)`.
    inline constexpr float kQrnSpikePerSampleProb = 0.01f;
    inline constexpr float kQrnSpikeAmpMul = 60.0f;

    // QRN burst (per-block): a TQrnStation is spawned to send a brief sparse
    // impulse train. Pascal: Contest.pas::GetAudio
    // `if Random < 0.01 then Stations.AddQrn`.
    inline constexpr float kQrnBurstPerBlockProb = 0.01f;
    inline constexpr float kQrnBurstAmpBase = 1.0e5f;       // amp = base · 10^(2·R)
    inline constexpr float kQrnBurstEnvelopeSpikeProb = 0.01f;

    // QRM (per-block): one chance in 5000 to spawn an interferer station.
    // Pascal: Contest.pas::GetAudio `Random < 0.0002`.
    inline constexpr float kQrmSpawnPerBlockProb = 0.0002f;
    inline constexpr float kQrmPitchSpreadHz = 300.0f;       // Gaussian σ/limit
    inline constexpr float kQrmAmpBase = 5000.0f;
    inline constexpr float kQrmAmpRange = 25000.0f;
    inline constexpr int kQrmWpmBase = 30;
    inline constexpr int kQrmWpmRange = 20;

    // QSK self-monitor envelope coefficients. The recovery is a single-pole
    // IIR `Rfg ← max(1 - blk/me.amp, Rfg·0.997 + 0.003)` — pulling Rfg back
    // toward 1 with a ~333-block (~15-s) time constant. Pascal: Contest.pas.
    inline constexpr float kQskAttackCoeff = 0.997f;
    inline constexpr float kQskReleaseAdd = 0.003f;

    // Self-monitor gain mapping. Slider in [0,1] maps to ±~26 dB about 0
    // (slider 0.75 → unity gain, matching the legacy "−15 dB" label).
    // Pascal: Contest.pas `Smg := Power(10, (Slider - 0.75) * 4)`.
    inline constexpr float kSelfMonGainSliderZero = 0.75f;
    inline constexpr float kSelfMonGainScale = 4.0f;

    // Morse key ramp: 5 ms Blackman-Harris attack/decay to suppress audible
    // key clicks. Pascal: VCL/MorseKey.pas `RiseTime := 0.005`.
    inline constexpr double kRiseTimeSeconds = 0.005;
    inline constexpr double kBlackmanHarrisStretch = 2.7;

    // Morse keying timing: at WPM = 30 and SR = 11025, one unit = 441 samples.
    // Formula `SamplesInUnit = round(0.1 · SR · 12 / WPM)`. Pascal:
    // VCL/MorseKey.pas::GetEnvelope. Kept in double: 0.1f is slightly
    // above 0.1 and turns the exact tie at 12 WPM (1102.5) into 1103.
    inline constexpr double kMorseUnitSecondsCoef = 0.1;
    inline constexpr int kMorseUnitsPerWpmRef = 12;

    // Blackman-Harris coefficients (4-term). Apple Vector DSP does not ship
    // a Blackman-Harris helper that matches the original's normalization, so
    // we re-derive in BlackmanHarris.cpp using these coefficients.
    // Pascal: VCL/MorseKey.pas::BlackmanHarrisKernel.
    inline constexpr double kBlackmanHarrisA0 = 0.35875;
    inline constexpr double kBlackmanHarrisA1 = 0.48829;
    inline constexpr double kBlackmanHarrisA2 = 0.14128;
    inline constexpr double kBlackmanHarrisA3 = 0.01168;

    // Moving-average low-pass: 3-pass cumulative-sum cascade approximating a
    // Gaussian. Pascal: Contest.pas `Filt.Points := Round(0.7 * SR / BW)`,
    // `Filt.Passes := 3`, `Filt.GainDb := 10 * Log10(500/BW)`.
    inline constexpr float kFilterPointsRatio = 0.7f;
    inline constexpr int kFilterPasses = 3;
    inline constexpr float kFilterGainRefBw = 500.0f;

    // AGC parameters. Equal in/out dB → unity gain at noise floor; attack
    // and hold both 14 ms (155 samples). Pascal: Contest.pas constructor.
    inline constexpr float kAgcNoiseInDb = 76.0f;
    inline constexpr float kAgcNoiseOutDb = 76.0f;
    inline constexpr int kAgcAttackSamples = 155;
    inline constexpr int kAgcHoldSamples = 155;

    // QSB (Rayleigh fading) bandwidth and flutter ranges. Pascal: DxStn.pas.
    inline constexpr float kQsbBandwidthBase = 0.1f;
    inline constexpr float kQsbBandwidthSpread = 0.5f;
    inline constexpr float kFlutterProb = 0.3f;
    inline constexpr float kFlutterBwBase = 3.0f;
    inline constexpr float kFlutterBwSpread = 30.0f;
}  // namespace Dsp

// ─── Simulation ─────────────────────────────────────────────────────────────
namespace Sim {
    // Generic patience counter for DX operators in any state except NeedQso.
    // Pascal: DxOper.pas `FULL_PATIENCE = 5`.
    inline constexpr int kFullPatience = 5;
    // Entering NeedQso uses a Rayleigh-distributed patience with mean 4.
    inline constexpr float kNeedQsoPatienceMean = 4.0f;

    // DX station amplitude is centered on the noise floor with a U-shaped
    // spread, so most stations are either notably weak or notably strong.
    // Pascal: DxStn.pas `Amplitude := 9000 + 18000 * (1 + RndUShaped)`.
    inline constexpr float kDxAmpBase = 9000.0f;
    inline constexpr float kDxAmpSpread = 18000.0f;

    // Per-station BFO offset: Gaussian σ/limit 300 Hz. Pascal: DxStn.pas.
    inline constexpr float kDxPitchSpreadHz = 300.0f;

    // LID error rates. 3% chance the LID sends a non-599 RST, 10% chance it
    // sends a corrupt NR with an "EEEEE" correction. Pascal: DxStn.pas.
    inline constexpr float kLidRstErrorProb = 0.03f;
    inline constexpr float kLidNrErrorProb = 0.10f;
    inline constexpr int kLidRstBase = 559;
    inline constexpr int kLidRstStep = 10;
    inline constexpr int kLidRstCount = 4;   // 559, 569, 579, 589

    // Cut-number substitutions in NrAsText. Pascal: Station.pas::NrAsText.
    inline constexpr float kCutZeroAsO_Prob = 0.40f;
    inline constexpr float kCutZeroAsT_Prob = 0.97f;  // applied after O test failed
    inline constexpr float kCutNineAsN_Prob = 0.97f;

    // IsMyCall Levenshtein-with-wildcard DP. Pascal: DxOper.pas::IsMyCall.
    // All three edit operations cost the same (2). 0 penalty → exact match;
    // ≤ 2 → "almost"; > 2 → reject. Keeping costs explicit so future tuning
    // (e.g. lowering substitution cost vs insertion) is a one-line change.
    inline constexpr int kLevSubstCost = 2;
    inline constexpr int kLevInsCost = 2;
    inline constexpr int kLevDelCost = 2;
    inline constexpr int kLevMatchThresh = 2;

    // Repeat-count when entering NeedQso outside Single/HST modes.
    // Pascal: DxOper.pas::SetState.
    inline constexpr float kRepeatProb = 0.10f;
    inline constexpr int kRepeatCount = 2;

    // LID mishearing probabilities — chance of inverting an IsMyCall result.
    // Pascal: DxOper.pas::IsMyCall epilogue.
    inline constexpr float kMishearStandardProb = 0.01f;
    inline constexpr float kMishearLidProb = 0.04f;

    // Caller spawn after CQ: Poisson(Activity/2) new TDxStations.
    // Pascal: Contest.pas::OnMeFinishedSending.
    inline constexpr float kCallerSpawnRateActivityDivisor = 2.0f;
}  // namespace Sim

// ─── Scoring ────────────────────────────────────────────────────────────────
namespace Scoring {
    // CRC32 seed for the WPX score-submission string. The polynomial is the
    // standard PKZIP/Ethernet table; only the seed differs from many sample
    // implementations. Pascal: ScoreDlg use of VCL/Crc32.pas.
    inline constexpr uint32_t kCrc32Seed = 0xC90C2086u;

    // Prefix extraction: WPX prefixes are 2..5 characters ending in a digit.
    // Pascal: Log.pas::ExtractPrefix.
    inline constexpr int kMinPrefixLen = 2;
    inline constexpr int kMaxPrefixLen = 5;

    // Log-row column widths. Format string in the original is
    //     ' hh:nn:ss  %-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s'
    // Pascal: Log.pas::LastQsoToScreen.
    inline constexpr int kLogCallWidth = 12;
    inline constexpr int kLogRstWidth = 3;
    inline constexpr int kLogNrWidth = 4;
    inline constexpr int kLogExchWidth = 5;
    inline constexpr int kLogErrWidth = 3;

    // HST scoring weights: Morse element cost. '.'=2, '-'=4, ' '=2, minus 1.
    // Pascal: Log.pas::CallToScore.
    inline constexpr int kHstDotCost = 2;
    inline constexpr int kHstDashCost = 4;
    inline constexpr int kHstSpaceCost = 2;
    inline constexpr int kHstStartPenalty = 1;
}  // namespace Scoring

// ─── UI ─────────────────────────────────────────────────────────────────────
namespace Ui {
    // Main window: fixed size, non-resizable. Pascal: Main.dfm
    // ClientWidth 700 / ClientHeight 413. Native macOS widgets are
    // taller and wider than their Windows equivalents at the same
    // point sizes, so the port scales the client area up by ~10%
    // horizontally and ~13% vertically. Documented as an accepted
    // platform delta in docs/parity-checklist.md.
    inline constexpr int kMainWindowWidth = 760;
    inline constexpr int kMainWindowHeight = 470;
    inline constexpr int kBottomPanelHeight = 160;    // Panel1 (was 119)
    inline constexpr int kRightPanelWidth = 212;      // Panel9
    inline constexpr int kRightPanelHeight = 308;
    inline constexpr int kSpacerHeight = 8;           // Panel5
    inline constexpr int kTopBevelHeight = 2;         // Bevel1

    // Histogram (PaintBox1 on Panel3). 48 bins × 5 minutes covers 4 hours.
    // Pascal: Log.pas::PaintHisto.
    inline constexpr int kHistogramBins = 48;
    inline constexpr int kHistogramBinMinutes = 5;
    inline constexpr int kHistogramStridePx = 4;       // x = i*4 + 1
    inline constexpr int kHistogramBarWidthPx = 3;     // FillRect width
    inline constexpr int kHistogramBaselinePx = 3;     // y = H - 3 - count*2
    inline constexpr int kHistogramBarUnitPx = 2;      // pixels per QSO

    // QSO-rate readout averages over the last min(5 min, elapsed). Pascal:
    // Log.pas::ShowRate.
    inline constexpr int kRateWindowMinutes = 5;

    // GUI update throttle (Hz). The simulation publishes new state into the
    // GuiUpdateQueue; a QTimer on the GUI thread drains at this rate. New v1.
    inline constexpr int kGuiUpdateHz = 30;
    inline constexpr int kLogRowQueueCap = 256;

    // Default font sizes (points). MS Sans Serif on Windows → Helvetica on
    // macOS (close metrics; documented as accepted parity delta).
    inline constexpr int kDefaultFontPt = 11;
    inline constexpr int kLogFontPt = 13;
    inline constexpr int kClockFontPt = 24;
    inline constexpr int kModeFontPt = 21;
    inline constexpr int kRateFontPt = 11;
    inline constexpr int kLogoFontPt = 35;
    inline constexpr int kHiScoreFontPt = 19;
    inline constexpr int kCallEditFontPt = 16;

    // Settings ranges enforced on UI inputs.
    inline constexpr int kWpmMin = 10;
    inline constexpr int kWpmMax = 120;
    inline constexpr int kWpmStep = 5;
    inline constexpr int kActivityMin = 1;
    inline constexpr int kActivityMax = 9;
    inline constexpr int kDurationMin = 1;
    inline constexpr int kDurationMax = 240;

    // CW Pitch combo box: 300..900 Hz in 50 Hz steps (13 items).
    inline constexpr int kPitchMinHz = 300;
    inline constexpr int kPitchMaxHz = 900;
    inline constexpr int kPitchStepHz = 50;
    // RX Bandwidth combo box: 100..600 Hz in 50 Hz steps (11 items).
    inline constexpr int kBandwidthMinHz = 100;
    inline constexpr int kBandwidthMaxHz = 600;
    inline constexpr int kBandwidthStepHz = 50;

    // RIT range and arrow-key step.
    inline constexpr int kRitMinHz = -500;
    inline constexpr int kRitMaxHz = 500;
    inline constexpr int kRitStepHz = 50;

    // Self-monitor menu cardinal points (dB).
    inline constexpr int kMonLevelMinDb = -60;
    inline constexpr int kMonLevelMaxDb = 20;
}  // namespace Ui

}  // namespace mr::constants
