// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of VCL/VolumCtl.pas (TVolumeControl). Look-ahead AGC with a
// Blackman-Harris-style attack shape and symmetric hold. The envelope
// is computed in log-magnitude space (so the attack shape is additive
// rather than multiplicative) and the gain curve is the standard
//
//     gain(env) = MaxOut · (1 - exp(-env / Beta)) / env
//
// which saturates smoothly at MaxOut while staying linear near the
// noise floor. Beta is solved from CalcBeta so that the configured
// NoiseIn maps to NoiseOut at unity-gain.

#pragma once

#include <cstddef>
#include <span>
#include <vector>

namespace mr::dsp {

class Agc {
public:
    Agc();

    // dB control: log-scaled in/out target levels. After either changes
    // the internal Beta is re-solved.
    void setNoiseInDb(float db);
    void setNoiseOutDb(float db);
    void setMaxOut(float maxOut);
    void setAttackSamples(int n);
    void setHoldSamples(int n);
    void setEnabled(bool on) { enabled_ = on; }

    [[nodiscard]] bool isOverload() const noexcept { return overload_; }
    [[nodiscard]] float maxOut() const noexcept { return maxOut_; }

    // Drops all delay-line state. Called by the Contest engine on
    // run-mode transitions.
    void reset();

    // Process a block of real samples in place. Output length equals
    // input length; samples are clamped to ±maxOut when bypassed.
    void process(std::span<float> data);

private:
    void recomputeBeta();
    void rebuildAttackShape();
    [[nodiscard]] float calcAgcGain();
    [[nodiscard]] float applyAgc(float v);

    float maxOut_ = 20000.0F;
    float noiseIn_ = 1.0F;
    float noiseOut_ = 2000.0F;
    float beta_ = 1.0F;
    float defaultGain_ = 2000.0F;
    int attackSamples_ = 28;
    int holdSamples_ = 28;
    int len_ = 0;
    int bufIdx_ = 0;
    bool enabled_ = true;
    bool overload_ = false;

    std::vector<float> realBuf_;
    std::vector<float> magBuf_;
    std::vector<float> attackShape_;
};

}  // namespace mr::dsp
