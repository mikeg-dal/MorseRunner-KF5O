// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reference data for the Swift MRSimulation module: whole contests.
//
// A deterministic robot operator plays each scenario against the C++
// Contest (CQ, copy a caller, send his call + number, sometimes with a
// '?' that it later corrects, TU / TU + my call, log the QSO, plus
// scripted aborts and odd F-keys). Everything it does is recorded as an
// action list; the Swift test replays those actions and must reproduce
// the per-block trace (player + every station's state, plus audio
// statistics) line for line. The robot only reads engine state, so the
// Swift side needs no robot.
//
// Output, per scenario NAME: Fixtures/sim/NAME.json (settings + actions)
// and Fixtures/sim/NAME.trace (one line per block, plus EV lines).

#include "golden_io.h"

#include "core/Constants.h"
#include "core/Random.h"
#include "simulation/CallsignDb.h"
#include "simulation/Contest.h"

#include <cstdio>
#include <limits>
#include <memory>
#include <string>
#include <vector>

using namespace golden;
using namespace mr::sim;

namespace {

std::string g_masterDta;

struct Action {
    int block;
    std::string json;
};

struct Scenario {
    std::string name;
    unsigned seed;
    ContestSettings settings;
    RunMode mode;
    int maxBlocks;
    bool stopByUserAt = false;  // requestStop at maxBlocks - 200
};

const char* kindOf(const Station& s) {
    if (dynamic_cast<const DxStation*>(&s)) return "D";
    if (dynamic_cast<const QrmStation*>(&s)) return "Q";
    if (dynamic_cast<const QrnStation*>(&s)) return "N";
    return "?";
}

std::string timeoutStr(int t) {
    return t == kNeverTimeout ? std::string("N") : std::to_string(t);
}

std::string traceLine(int b, Contest& c, const std::vector<float>& out) {
    double sum = 0, sq = 0;
    for (float x : out) { sum += x; sq += static_cast<double>(x) * x; }
    auto& me = c.player();
    char buf[512];
    std::snprintf(buf, sizeof buf, "%d me=%d,%llu,%d,%s,%zu|", b, static_cast<int>(me.state()),
                  static_cast<unsigned long long>(me.msg().to_ullong()), me.nr(),
                  me.hisCall().c_str(), me.pieceCount());
    std::string line = buf;
    for (auto& sp : c.stations()) {
        const Station& s = *sp;
        std::snprintf(buf, sizeof buf, "%s:%s,%d,%s,%llu,w%d,p%d,a%s,n%d,r%d", kindOf(s),
                      s.myCall().c_str(), static_cast<int>(s.state()),
                      timeoutStr(s.timeout()).c_str(),
                      static_cast<unsigned long long>(s.msg().to_ullong()), s.wpm(),
                      s.pitchHz(), num(s.amplitude()).c_str(), s.nr(), s.rst());
        line += buf;
        if (auto* dx = dynamic_cast<const DxStation*>(&s)) {
            const auto& op = dx->operatorState();
            std::snprintf(buf, sizeof buf, ",o%d,pt%d,rc%d,sk%d", static_cast<int>(op.state()),
                          op.patience(), op.repeatCount(), op.skills());
            line += buf;
        }
        line += ";";
    }
    line += "|" + num(sum) + "," + num(sq);
    return line;
}

std::string settingsJson(const ContestSettings& s) {
    return "{\"myCallsign\":" + str(s.myCallsign) + ",\"wpm\":" + num(s.wpm)
         + ",\"pitchHz\":" + num(s.pitchHz) + ",\"rxBandwidthHz\":" + num(s.rxBandwidthHz)
         + ",\"ritHz\":" + num(s.ritHz) + ",\"qsk\":" + (s.qsk ? "true" : "false")
         + ",\"qrn\":" + (s.qrn ? "true" : "false") + ",\"qrm\":" + (s.qrm ? "true" : "false")
         + ",\"qsb\":" + (s.qsb ? "true" : "false")
         + ",\"flutter\":" + (s.flutter ? "true" : "false")
         + ",\"lids\":" + (s.lids ? "true" : "false") + ",\"activity\":" + num(s.activity)
         + ",\"durationMinutes\":" + num(s.durationMinutes)
         + ",\"selfMonGain01\":" + num(s.selfMonGain01)
         + ",\"callsFromKeyer\":" + (s.callsFromKeyer ? "true" : "false") + "}";
}

// The robot operator. Reads engine state, never draws random numbers.
struct Robot {
    enum Phase { Idle, WaitCallers, Working } phase = Idle;
    int wait = 0;
    int lastAction = -1000;
    int qsoNo = 0;
    std::string dxCall;
    bool corrupted = false;
    bool sawDxSend = false;

    DxStation* find(Contest& c, const std::string& call) {
        for (auto& sp : c.stations()) {
            if (auto* dx = dynamic_cast<DxStation*>(sp.get()); dx && dx->myCall() == call
                && !dx->shouldRemove()) {
                return dx;
            }
        }
        return nullptr;
    }

    void step(int b, Contest& c, RunMode mode, std::vector<Action>& acts) {
        auto send = [&](Message m, const std::string& field = {}) {
            c.playerSendMessage(m, field);
            acts.push_back({b, "{\"b\":" + num(b) + ",\"a\":\"send\",\"m\":"
                                   + num(static_cast<int>(m)) + ",\"call\":" + str(field) + "}"});
            lastAction = b;
        };
        auto edit = [&](const std::string& field) {
            const bool ok = c.playerEditedCall(field);
            acts.push_back({b, "{\"b\":" + num(b) + ",\"a\":\"edit\",\"call\":" + str(field)
                                   + ",\"ok\":" + (ok ? "true" : "false") + "}"});
        };
        auto log = [&](const std::string& call) {
            c.qsoLogged(call);
            acts.push_back({b, "{\"b\":" + num(b) + ",\"a\":\"log\",\"call\":" + str(call) + "}"});
        };
        auto abort = [&]() {
            const auto info = c.playerAbortSend();
            acts.push_back({b, "{\"b\":" + num(b) + ",\"a\":\"abort\",\"his\":"
                                   + (info.hadHisCall ? "true" : "false") + ",\"nr\":"
                                   + (info.hadNr ? "true" : "false") + "}"});
            lastAction = b;
        };

        // Scripted odd inputs, independent of the QSO flow.
        if (b == 140) send(Message::Qm);
        if (b == 610) send(Message::B4);
        if (b == 890) send(Message::Nil);
        if (b % 731 == 400 && c.playerSending()) { abort(); phase = Idle; return; }
        if (b == 1200) send(Message::MyCall);

        if (c.playerSending()) {
            // Mid-send correction while our call is being keyed.
            if (phase == Working && corrupted && b % 3 == 0) {
                edit(dxCall);
                corrupted = false;
            }
            return;
        }
        ++wait;
        const bool autoCallers = mode == RunMode::Single || mode == RunMode::Hst;

        switch (phase) {
            case Idle:
                if (autoCallers) { phase = WaitCallers; wait = 0; break; }
                if (b - lastAction >= 15) {
                    bool dxSending = false;
                    for (auto& sp : c.stations()) {
                        if (dynamic_cast<DxStation*>(sp.get())
                            && sp->state() == StationState::Sending) dxSending = true;
                    }
                    if (!dxSending) {
                        send(qsoNo % 4 == 3 ? Message::Cq : Message::Cq);
                        phase = WaitCallers;
                        wait = 0;
                    }
                }
                break;
            case WaitCallers: {
                DxStation* pick = nullptr;
                for (auto& sp : c.stations()) {
                    auto* dx = dynamic_cast<DxStation*>(sp.get());
                    if (dx && !dx->isFinished() && dx->state() == StationState::Listening
                        && dx->operatorState().state() == OperatorState::NeedQso) {
                        pick = dx;
                        break;
                    }
                }
                if (pick) {
                    dxCall = pick->myCall();
                    std::string field = dxCall;
                    corrupted = (qsoNo % 5 == 3) && field.size() > 3;
                    if (corrupted) field.back() = '?';
                    send(Message::HisCall, field);
                    send(Message::Nr);
                    phase = Working;
                    wait = 0;
                    sawDxSend = false;
                } else if (wait > 300) {
                    phase = Idle;
                }
                break;
            }
            case Working: {
                DxStation* dx = find(c, dxCall);
                if (!dx || dx->operatorState().state() == OperatorState::Failed || wait > 400) {
                    phase = Idle;
                    break;
                }
                if (dx->state() == StationState::Sending) { sawDxSend = true; break; }
                if (!sawDxSend) break;
                if (corrupted) {
                    edit(dxCall);
                    send(Message::HisCall, dxCall);
                    send(Message::Nr);
                    corrupted = false;
                    sawDxSend = false;
                    wait = 0;
                    break;
                }
                send(Message::Tu);
                if (qsoNo % 2 == 0) send(Message::MyCall);
                log(dxCall);
                ++qsoNo;
                phase = Idle;
                break;
            }
        }
    }
};

void run(const Scenario& sc) {
    auto& rng = mr::core::Random::instance();
    rng.reseed(sc.seed);
    auto db = std::make_unique<CallsignDb>();
    if (!db->loadFromFile(g_masterDta)) {
        std::fprintf(stderr, "cannot load %s\n", g_masterDta.c_str());
        std::exit(1);
    }
    Contest c(std::move(db), mr::constants::Audio::kDefaultBufferSamples, rng);
    c.setSettings(sc.settings);
    c.setRunMode(sc.mode);

    std::string trace;
    std::vector<Action> acts;
    c.setQsoCompletedCallback([&](const Contest::CompletedQso& q) {
        trace += "EV qso " + q.call + " " + num(q.rst) + " " + num(q.nr) + "\n";
    });
    bool ended = false;
    c.setEndOfSessionCallback([&](RunMode m, bool byUser) {
        trace += "EV end " + num(static_cast<int>(m)) + " " + (byUser ? "1" : "0") + "\n";
        ended = true;
    });
    c.setPlayerPieceFinishedCallback([&]() { trace += "EV piece\n"; });

    Robot bot;
    std::vector<float> out(static_cast<std::size_t>(mr::constants::Audio::kDefaultBufferSamples));
    for (int b = 0; b < sc.maxBlocks && !ended; ++b) {
        if (sc.stopByUserAt && b == sc.maxBlocks - 200) {
            c.requestStop();
            acts.push_back({b, "{\"b\":" + num(b) + ",\"a\":\"stop\"}"});
        }
        bot.step(b, c, sc.mode, acts);
        c.renderNextBlock(out);
        trace += traceLine(b, c, out) + "\n";
    }

    std::string aj = "[";
    for (std::size_t i = 0; i < acts.size(); ++i) aj += (i ? "," : "") + acts[i].json;
    aj += "]";
    writeText("sim/" + sc.name + ".json",
              "{\"seed\":" + num(sc.seed) + ",\"mode\":" + num(static_cast<int>(sc.mode))
                  + ",\"maxBlocks\":" + num(sc.maxBlocks)
                  + ",\"settings\":" + settingsJson(sc.settings) + ",\"actions\":" + aj + "}");
    writeText("sim/" + sc.name + ".trace", trace);
    std::printf("%s: %zu actions, %d qsos\n", sc.name.c_str(), acts.size(), bot.qsoNo);
}

}  // namespace

int main(int argc, char** argv) {
    init(argc, argv);
    g_masterDta = (argc > 2) ? argv[2] : MR_SOURCE_DIR "/resources/data/Master.dta";

    ContestSettings base;  // C++ defaults: VE3NEA, 30 wpm, 600 Hz, 500 Hz, all on, activity 3
    base.durationMinutes = 2;

    std::vector<Scenario> list;
    list.push_back({"pileup_default", 1, base, RunMode::PileUp, 2700});

    ContestSettings odd = base;
    odd.wpm = 40; odd.pitchHz = 450; odd.rxBandwidthHz = 300; odd.ritHz = 100;
    odd.qsk = false; odd.lids = false; odd.qsb = false; odd.activity = 6;
    odd.selfMonGain01 = 0.5F; odd.myCallsign = "KF5O";
    list.push_back({"pileup_odd", 7, odd, RunMode::PileUp, 2700});

    ContestSettings single = base; single.durationMinutes = 1;
    list.push_back({"single", 3, single, RunMode::Single, 1400});

    ContestSettings wpx = base; wpx.durationMinutes = 1; wpx.wpm = 25;
    list.push_back({"wpx", 4, wpx, RunMode::Wpx, 1400});

    ContestSettings hst = base; hst.durationMinutes = 1; hst.wpm = 35;
    hst.qrn = hst.qrm = hst.qsb = hst.flutter = hst.lids = false;
    hst.activity = 4; hst.rxBandwidthHz = 600;
    list.push_back({"hst", 5, hst, RunMode::Hst, 1400});

    ContestSettings stop = base; stop.durationMinutes = 5; stop.wpm = 120;
    list.push_back({"stopped_120wpm", 9, stop, RunMode::PileUp, 900, true});

    for (const auto& sc : list) run(sc);
    return 0;
}
