// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reference data for the Swift port's MRDSP module. Every sample array
// is raw float32 (.f32); each component has a JSON manifest describing
// the cases. Float parameters in the manifests are written as their
// IEEE-754 bit patterns ("...Bits") so no decimal round trip is involved.
//
// Layout under Fixtures/dsp/:
//   signal_re.f32, signal_im.f32   shared deterministic complex test input
//   agc_input.f32                  loud/quiet/silent test input for the AGC
//   bh.json + bh/<len>.f32         blackmanHarrisStep
//   keyer.json + keyer/<i>.f32     MorseKeyer envelopes
//   movavg.json + movavg/<i>.f32   MovingAverage (real or complex)
//   pingpong.json + pingpong/<i>.f32
//   quickavg.json + quickavg/<i>.f32
//   qsb.json + qsb/<i>.f32
//   modulator.json + modulator/<i>.f32
//   agc.json + agc/<i>.f32

#include "golden_io.h"

#include "core/Constants.h"
#include "core/DelphiRound.h"
#include "core/Random.h"
#include "dsp/Agc.h"
#include "dsp/BlackmanHarris.h"
#include "dsp/ComplexBuf.h"
#include "dsp/Modulator.h"
#include "dsp/MorseKeyer.h"
#include "dsp/MovingAverage.h"
#include "dsp/PingPongFilter.h"
#include "dsp/Qsb.h"
#include "dsp/QuickAverage.h"

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstdint>
#include <random>
#include <span>
#include <string>
#include <vector>

using namespace golden;
using namespace mr::dsp;

namespace {

constexpr int kSR = mr::constants::Audio::kSampleRate;
constexpr std::size_t kSignalLen = 65536;

std::string bits(float f) { return num(static_cast<unsigned>(std::bit_cast<std::uint32_t>(f))); }

std::string jbool(bool b) { return b ? "true" : "false"; }

// Joins JSON objects into an array.
struct JArr {
    std::string s = "[";
    bool first = true;
    void add(const std::string& obj) {
        if (!first) s += ",";
        first = false;
        s += obj;
    }
    std::string done() const { return s + "]"; }
};

std::vector<float> g_re;
std::vector<float> g_im;
std::vector<float> g_agcIn;

void makeSignals() {
    // A two-tone complex signal with uniform noise and a few spikes;
    // computed in double then narrowed, values in the low thousands like
    // the real I/Q mix.
    std::mt19937 mt(12345u);
    std::uniform_real_distribution<double> u(-1.0, 1.0);
    g_re.resize(kSignalLen);
    g_im.resize(kSignalLen);
    for (std::size_t n = 0; n < kSignalLen; ++n) {
        const double t = static_cast<double>(n);
        double re = 1500.0 * std::sin(0.031 * t) + 700.0 * std::sin(0.4 * t + 1.0)
                    + 300.0 * u(mt);
        double im = 1500.0 * std::cos(0.031 * t) - 500.0 * std::sin(0.17 * t)
                    + 300.0 * u(mt);
        if (n % 4099 == 17) re += 40000.0;
        if (n % 3001 == 5) im -= 25000.0;
        g_re[n] = static_cast<float>(re);
        g_im[n] = static_cast<float>(im);
    }
    writeFloats("dsp/signal_re.f32", g_re);
    writeFloats("dsp/signal_im.f32", g_im);

    // AGC input: sections of noise-level, loud carrier, very loud
    // bursts and digital silence.
    g_agcIn.resize(kSignalLen);
    for (std::size_t n = 0; n < kSignalLen; ++n) {
        const std::size_t sec = (n / 2500) % 6;
        const double t = static_cast<double>(n);
        double amp = 0.0;
        switch (sec) {
            case 0: amp = 3000.0; break;     // noise floor-ish
            case 1: amp = 60000.0; break;    // loud
            case 2: amp = 0.0; break;        // silence
            case 3: amp = 800000.0; break;   // very loud
            case 4: amp = 50.0; break;       // quiet
            default: amp = 12000.0; break;
        }
        const double v = amp * (0.7 * std::sin(0.35 * t) + 0.3 * u(mt));
        g_agcIn[n] = static_cast<float>(v);
    }
    writeFloats("dsp/agc_input.f32", g_agcIn);
}

void dumpBlackmanHarris() {
    JArr j;
    for (int len : {0, 1, 2, 3, 10, 100, 149, 150, 297, 1000}) {
        writeFloats("dsp/bh/" + num(len) + ".f32", blackmanHarrisStep(len));
        j.add(num(len));
    }
    writeText("dsp/bh.json", j.done());
}

void dumpKeyer() {
    const std::vector<std::string> texts = {
        "E", "T", "PARIS", "CQ TEST", "HHHHH 55555 CQ TEST VE3NEA",
        "5NN 001 TU", "ve3nea/p?", "-.-. --.-~", "E_T  ", "@!", "", " ",
    };
    const std::vector<int> wpms = {10, 12, 15, 18, 20, 25, 28, 30, 35, 40, 45, 50,
                                   60, 70, 80, 85, 88, 89, 90, 100, 110, 120};
    JArr j;
    int idx = 0;
    auto emit = [&](const std::string& text, int sr, int wpm, bool viaSetters) {
        MorseKeyer k(sr, wpm);
        if (viaSetters) {
            // Constructed at defaults, then retuned like Station does.
            MorseKeyer k2(kSR, 30);
            k2.setSampleRate(sr);
            k2.setWpm(wpm);
            k = k2;
        }
        const auto env = k.renderEnvelope(text);
        const std::string file = num(idx) + ".f32";
        writeFloats("dsp/keyer/" + file, env);
        j.add("{\"text\":" + str(text) + ",\"sr\":" + num(sr) + ",\"wpm\":" + num(wpm)
              + ",\"viaSetters\":" + jbool(viaSetters) + ",\"samplesPerUnit\":"
              + num(k.samplesPerUnit()) + ",\"rampSamples\":" + num(k.rampSamples())
              + ",\"count\":" + num(env.size()) + ",\"file\":" + str(file) + "}");
        ++idx;
    };
    // Full WPM sweep for short texts; longer texts at the speeds that
    // matter (Delphi-rounding ties 12/28/60, default 30, and the
    // ramp-overlap region above ~88 WPM) to keep the fixture small.
    const std::vector<int> someWpms = {12, 28, 30, 60, 89, 120};
    for (const auto& t : texts) {
        const bool shortText = t.size() <= 5;
        const auto& ws = (t == "HHHHH 55555 CQ TEST VE3NEA")
                             ? std::vector<int>{30, 60, 85, 88, 89, 90, 100, 110, 120}
                             : (shortText ? wpms : someWpms);
        for (int w : ws) {
            emit(t, kSR, w, false);
        }
    }
    for (int sr : {8000, 22050, 44100}) {
        for (int w : {30, 90}) {
            emit("TEST", sr, w, true);
        }
    }
    emit("PARIS", kSR, 47, true);
    writeText("dsp/keyer.json", j.done());
}

struct MaCfg {
    int points, passes, block;
    float gainDb;
    int inLen, blocks;
    bool complex;
};

void dumpMovingAverage() {
    std::vector<MaCfg> cfgs = {
        {16, 3, 64, 0.0F, 64, 20, false},
        {16, 3, 64, 0.0F, 64, 20, true},
        {129, 3, 512, 0.0F, 512, 12, false},
        {1, 1, 32, 6.0F, 32, 10, false},
        {7, 5, 100, -3.5F, 100, 15, true},
        // Mismatched input lengths (degenerate PushArray paths).
        {16, 3, 64, 0.0F, 32, 12, false},
        {16, 3, 64, 0.0F, 100, 8, false},
        {16, 3, 64, 0.0F, 200, 6, true},
    };
    // Contest bandwidth configurations.
    for (int bwi = 100; bwi <= 600; bwi += 100) {
        const float bw = static_cast<float>(bwi);
        const int points = std::max(
            1, mr::core::delphiRound(static_cast<double>(
                                     mr::constants::Dsp::kFilterPointsRatio * static_cast<float>(kSR) / bw)));
        const float gainDb = 10.0F * std::log10(mr::constants::Dsp::kFilterGainRefBw / bw);
        cfgs.push_back({points, 3, 512, gainDb, 512, 12, true});
        cfgs.push_back({points, 3, 128, gainDb, 128, 20, false});
    }
    JArr j;
    int idx = 0;
    for (const auto& c : cfgs) {
        MovingAverage m;
        m.configure(c.points, c.passes, c.block, c.gainDb);
        std::vector<float> outAll;
        std::size_t off = 0;
        for (int b = 0; b < c.blocks; ++b) {
            const auto inLen = static_cast<std::size_t>(c.inLen);
            if (c.complex) {
                ComplexBuf buf;
                buf.re.assign(g_re.begin() + static_cast<std::ptrdiff_t>(off),
                              g_re.begin() + static_cast<std::ptrdiff_t>(off + inLen));
                buf.im.assign(g_im.begin() + static_cast<std::ptrdiff_t>(off),
                              g_im.begin() + static_cast<std::ptrdiff_t>(off + inLen));
                m.processComplex(buf);
                outAll.insert(outAll.end(), buf.re.begin(), buf.re.end());
                outAll.insert(outAll.end(), buf.im.begin(), buf.im.end());
            } else {
                std::vector<float> out(inLen, -7.0F);
                m.process(std::span<const float>(g_re.data() + off, inLen), out);
                outAll.insert(outAll.end(), out.begin(), out.end());
            }
            off += inLen;
        }
        const std::string file = num(idx) + ".f32";
        writeFloats("dsp/movavg/" + file, outAll);
        j.add("{\"points\":" + num(c.points) + ",\"passes\":" + num(c.passes)
              + ",\"block\":" + num(c.block) + ",\"gainDbBits\":" + bits(c.gainDb)
              + ",\"inLen\":" + num(c.inLen) + ",\"blocks\":" + num(c.blocks)
              + ",\"complex\":" + jbool(c.complex) + ",\"file\":" + str(file) + "}");
        ++idx;
    }

    // Setter sequence: retune mid-stream (setGainDb keeps state,
    // setPoints/setPasses/setSamplesInInput reset it).
    {
        MovingAverage m;
        m.configure(32, 3, 64, 0.0F);
        std::vector<float> outAll;
        std::size_t off = 0;
        auto run = [&](int n) {
            for (int b = 0; b < n; ++b) {
                const auto len = static_cast<std::size_t>(m.samplesInInput());
                std::vector<float> out(len);
                m.process(std::span<const float>(g_re.data() + off, len), out);
                outAll.insert(outAll.end(), out.begin(), out.end());
                off += len;
            }
        };
        run(3);
        m.setGainDb(4.0F);
        run(3);
        m.setPoints(20);
        run(3);
        m.setPasses(2);
        run(3);
        m.setSamplesInInput(48);
        run(3);
        m.setPoints(20);  // no-op
        m.reset();
        run(2);
        writeFloats("dsp/movavg/setters.f32", outAll);
    }
    writeText("dsp/movavg.json", j.done());
}

void dumpPingPong() {
    JArr j;
    int idx = 0;
    auto runCase = [&](int bwi, int block, int blocks, int resetAt) {
        const float bw = static_cast<float>(bwi);
        const int points = std::max(
            1, mr::core::delphiRound(static_cast<double>(
                                     mr::constants::Dsp::kFilterPointsRatio * static_cast<float>(kSR) / bw)));
        const float gainDb = 10.0F * std::log10(mr::constants::Dsp::kFilterGainRefBw / bw);
        PingPongFilter f;
        f.configure(points, 3, block, gainDb);
        std::vector<float> outAll;
        std::vector<int> counts;
        std::size_t off = 0;
        for (int b = 0; b < blocks; ++b) {
            if (b == resetAt) f.reset();
            const auto len = static_cast<std::size_t>(block);
            ComplexBuf buf;
            buf.re.assign(g_re.begin() + static_cast<std::ptrdiff_t>(off),
                          g_re.begin() + static_cast<std::ptrdiff_t>(off + len));
            buf.im.assign(g_im.begin() + static_cast<std::ptrdiff_t>(off),
                          g_im.begin() + static_cast<std::ptrdiff_t>(off + len));
            f.process(buf);
            outAll.insert(outAll.end(), buf.re.begin(), buf.re.end());
            outAll.insert(outAll.end(), buf.im.begin(), buf.im.end());
            counts.push_back(static_cast<int>(f.blockCount()));
            off += len;
        }
        const std::string file = num(idx) + ".f32";
        writeFloats("dsp/pingpong/" + file, outAll);
        j.add("{\"bw\":" + num(bwi) + ",\"points\":" + num(points) + ",\"gainDbBits\":"
              + bits(gainDb) + ",\"block\":" + num(block) + ",\"blocks\":" + num(blocks)
              + ",\"resetAt\":" + num(resetAt) + ",\"blockCounts\":" + arr(counts)
              + ",\"file\":" + str(file) + "}");
        ++idx;
    };
    for (int bw = 100; bw <= 600; bw += 50) {
        runCase(bw, 512, 25, -1);
    }
    runCase(250, 128, 45, -1);
    runCase(500, 2048, 22, -1);
    runCase(300, 512, 30, 14);
    writeText("dsp/pingpong.json", j.done());
}

void dumpQuickAverage() {
    JArr j;
    int idx = 0;
    const std::vector<std::pair<int, int>> cfgs = {
        {128, 4}, {16, 2}, {1, 1}, {7, 8}, {5, 20}, {300, 3}, {0, 0}, {3, -2}};
    constexpr int kN = 5000;
    for (const auto& [pts, pas] : cfgs) {
        QuickAverage q;
        if (!(pts == 128 && pas == 4)) {
            q.setPasses(pas);
            q.setPoints(pts);
        }
        std::vector<float> real;
        for (int i = 0; i < kN; ++i) real.push_back(q.filter(g_re[static_cast<std::size_t>(i)] * 0.001F));
        q.reset();
        std::vector<float> cplx;
        for (int i = 0; i < kN; ++i) {
            float r = 0.0F;
            float im = 0.0F;
            q.filterComplex(g_re[static_cast<std::size_t>(i)], g_im[static_cast<std::size_t>(i)], r, im);
            cplx.push_back(r);
            cplx.push_back(im);
        }
        std::vector<float> mod;
        for (int i = 0; i < kN; ++i) {
            mod.push_back(q.filteredModule(g_im[static_cast<std::size_t>(i)] * 0.01F,
                                           g_re[static_cast<std::size_t>(i)] * 0.01F));
        }
        const std::string f = num(idx);
        writeFloats("dsp/quickavg/" + f + "_real.f32", real);
        writeFloats("dsp/quickavg/" + f + "_complex.f32", cplx);
        writeFloats("dsp/quickavg/" + f + "_module.f32", mod);
        j.add("{\"points\":" + num(pts) + ",\"passes\":" + num(pas) + ",\"n\":" + num(kN)
              + ",\"pointsAfter\":" + num(q.points()) + ",\"passesAfter\":"
              + num(q.passes()) + ",\"file\":" + str(f) + "}");
        ++idx;
    }
    writeText("dsp/quickavg.json", j.done());
}

void dumpQsb() {
    auto& rng = mr::core::Random::instance();
    JArr j;
    int idx = 0;
    auto runCase = [&](unsigned seed, int bufSize, float bw, int arrLen, int blocks,
                       bool ones) {
        rng.reseed(seed);
        Qsb q(bufSize, rng);
        q.setBandwidth(bw);
        std::vector<float> outAll;
        std::size_t off = 0;
        for (int b = 0; b < blocks; ++b) {
            std::vector<float> arr(static_cast<std::size_t>(arrLen), 1.0F);
            if (!ones) {
                std::copy(g_re.begin() + static_cast<std::ptrdiff_t>(off),
                          g_re.begin() + static_cast<std::ptrdiff_t>(off) + arrLen, arr.begin());
                off += static_cast<std::size_t>(arrLen);
            }
            q.applyTo(arr);
            outAll.insert(outAll.end(), arr.begin(), arr.end());
        }
        // The draw that follows proves the generator was consumed exactly.
        const float nextDraw = rng.uniform01();
        const std::string file = num(idx) + ".f32";
        writeFloats("dsp/qsb/" + file, outAll);
        j.add("{\"seed\":" + num(seed) + ",\"bufSize\":" + num(bufSize) + ",\"bwBits\":"
              + bits(bw) + ",\"bandwidthBits\":" + bits(q.bandwidth()) + ",\"arrLen\":"
              + num(arrLen) + ",\"blocks\":" + num(blocks) + ",\"ones\":" + jbool(ones)
              + ",\"nextUniformBits\":" + bits(nextDraw) + ",\"file\":"
              + str(file) + "}");
        ++idx;
    };
    for (unsigned seed : {1u, 42u}) {
        for (float bw : {0.1F, 0.35F, 0.6F, 3.0F, 15.0F, 33.0F}) {
            runCase(seed, 512, bw, 512, 40, true);
        }
    }
    runCase(7, 512, 0.25F, 512, 30, false);
    runCase(9, 128, 0.4F, 128, 60, true);
    runCase(11, 2048, 5.0F, 2048, 12, true);
    runCase(13, 512, 0.2F, 700, 10, true);   // partial sub-block tail
    runCase(15, 512, -1.0F, 512, 8, true);   // rejected bandwidth: stays 0.1
    runCase(17, 3, 0.5F, 7, 5, true);        // tiny buffers, subBlock clamps to 1
    writeText("dsp/qsb.json", j.done());
}

void dumpModulator() {
    JArr j;
    int idx = 0;
    auto runCase = [&](int sr, float pitch, float pitch2, int block, int blocks,
                       int switchAt) {
        Modulator m(sr, pitch);
        std::vector<float> outAll;
        std::vector<int> tableSizes;
        std::vector<std::uint32_t> freqBits;
        std::size_t off = 0;
        for (int b = 0; b < blocks; ++b) {
            if (b == switchAt) m.setCarrierFreq(pitch2);
            const auto len = static_cast<std::size_t>(block);
            ComplexBuf buf;
            buf.re.assign(g_re.begin() + static_cast<std::ptrdiff_t>(off),
                          g_re.begin() + static_cast<std::ptrdiff_t>(off + len));
            buf.im.assign(g_im.begin() + static_cast<std::ptrdiff_t>(off),
                          g_im.begin() + static_cast<std::ptrdiff_t>(off + len));
            std::vector<float> out(len);
            m.modulate(buf, out);
            outAll.insert(outAll.end(), out.begin(), out.end());
            tableSizes.push_back(m.tableSize());
            freqBits.push_back(std::bit_cast<std::uint32_t>(m.carrierFreq()));
            off += len;
        }
        // Unit inputs expose the sin and cos tables directly.
        m.reset();
        ComplexBuf unit;
        unit.resize(static_cast<std::size_t>(m.tableSize()));
        std::fill(unit.re.begin(), unit.re.end(), 1.0F);
        std::vector<float> sn(unit.size());
        m.modulate(unit, sn);
        m.reset();
        std::fill(unit.re.begin(), unit.re.end(), 0.0F);
        std::fill(unit.im.begin(), unit.im.end(), -1.0F);
        std::vector<float> cs(unit.size());
        m.modulate(unit, cs);
        outAll.insert(outAll.end(), sn.begin(), sn.end());
        outAll.insert(outAll.end(), cs.begin(), cs.end());

        std::vector<unsigned> fb(freqBits.begin(), freqBits.end());
        const std::string file = num(idx) + ".f32";
        writeFloats("dsp/modulator/" + file, outAll);
        j.add("{\"sr\":" + num(sr) + ",\"pitchBits\":" + bits(pitch) + ",\"pitch2Bits\":"
              + bits(pitch2) + ",\"block\":" + num(block) + ",\"blocks\":" + num(blocks)
              + ",\"switchAt\":" + num(switchAt) + ",\"tableSizes\":" + arr(tableSizes)
              + ",\"carrierFreqBits\":" + arr(fb) + ",\"file\":" + str(file) + "}");
        ++idx;
    };
    for (int p = 300; p <= 900; p += 50) {
        runCase(kSR, static_cast<float>(p), 0.0F, 512, 7, -1);
    }
    runCase(kSR, 441.0F, 0.0F, 512, 4, -1);
    runCase(kSR, 600.0F, 450.0F, 512, 8, 3);
    runCase(kSR, 600.0F, 600.0F, 512, 5, 2);   // same pitch: no reset
    runCase(kSR, 600.0F, -5.0F, 512, 5, 2);    // rejected pitch
    runCase(kSR, 500.0F, 0.0F, 300, 9, -1);
    runCase(kSR, 20000.0F, 0.0F, 64, 4, -1);   // table clamps to 2
    runCase(8000, 650.0F, 0.0F, 512, 5, -1);
    writeText("dsp/modulator.json", j.done());
}

struct AgcCfg {
    bool contest;   // Contest's settings vs constructor defaults
    float noiseInDb, noiseOutDb, maxOut;
    int attack, hold;
    bool enabled;
    int block, blocks, resetAt;
    float inScale;
};

void dumpAgc() {
    using namespace mr::constants::Dsp;
    const std::vector<AgcCfg> cfgs = {
        {true, kAgcNoiseInDb, kAgcNoiseOutDb, 20000.0F, kAgcAttackSamples, kAgcHoldSamples,
         true, 512, 120, -1, 1.0F},
        {true, kAgcNoiseInDb, kAgcNoiseOutDb, 20000.0F, kAgcAttackSamples, kAgcHoldSamples,
         true, 128, 200, 77, 1.0F},
        {false, 0, 0, 0, 0, 0, true, 512, 40, -1, 1.0F},
        {true, 0.0F, 60.0F, 20000.0F, 155, 155, true, 512, 60, -1, 1.0F},
        {true, 10.0F, 90.0F, 30000.0F, 10, 40, true, 256, 80, -1, 1.0F},
        {true, 0.0F, 60.0F, 20000.0F, 155, 155, false, 512, 40, -1, 0.05F},
        {true, kAgcNoiseInDb, kAgcNoiseOutDb, 20000.0F, 1, 0, true, 512, 30, -1, 1.0F},
    };
    JArr j;
    int idx = 0;
    for (const auto& c : cfgs) {
        Agc a;
        if (c.contest) {
            a.setMaxOut(c.maxOut);
            a.setNoiseInDb(c.noiseInDb);
            a.setNoiseOutDb(c.noiseOutDb);
            a.setAttackSamples(c.attack);
            a.setHoldSamples(c.hold);
            a.setEnabled(c.enabled);
        }
        std::vector<float> outAll;
        std::vector<int> overload;
        std::size_t off = 0;
        for (int b = 0; b < c.blocks; ++b) {
            if (b == c.resetAt) a.reset();
            const auto len = static_cast<std::size_t>(c.block);
            std::vector<float> data(len);
            for (std::size_t i = 0; i < len; ++i) {
                data[i] = g_agcIn[(off + i) % kSignalLen] * c.inScale;
            }
            a.process(data);
            outAll.insert(outAll.end(), data.begin(), data.end());
            overload.push_back(a.isOverload() ? 1 : 0);
            off += len;
        }
        const std::string file = num(idx) + ".f32";
        writeFloats("dsp/agc/" + file, outAll);
        j.add("{\"contest\":" + jbool(c.contest) + ",\"noiseInDbBits\":" + bits(c.noiseInDb)
              + ",\"noiseOutDbBits\":" + bits(c.noiseOutDb) + ",\"maxOutBits\":"
              + bits(c.maxOut) + ",\"attack\":" + num(c.attack) + ",\"hold\":" + num(c.hold)
              + ",\"enabled\":" + jbool(c.enabled) + ",\"block\":" + num(c.block)
              + ",\"blocks\":" + num(c.blocks) + ",\"resetAt\":" + num(c.resetAt)
              + ",\"inScaleBits\":" + bits(c.inScale) + ",\"overload\":" + arr(overload)
              + ",\"maxOutAfterBits\":" + bits(a.maxOut()) + ",\"file\":" + str(file) + "}");
        ++idx;
    }
    writeText("dsp/agc.json", j.done());
}

}  // namespace

int main(int argc, char** argv) {
    golden::init(argc, argv);
    makeSignals();
    dumpBlackmanHarris();
    dumpKeyer();
    dumpMovingAverage();
    dumpPingPong();
    dumpQuickAverage();
    dumpQsb();
    dumpModulator();
    dumpAgc();
    return 0;
}
