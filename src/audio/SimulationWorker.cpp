// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "audio/SimulationWorker.h"

#include "core/Constants.h"
#include "core/Logging.h"
#include "core/Random.h"
#include "core/ThreadNames.h"
#include "simulation/CallsignDb.h"
#include "simulation/CallsignSource.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include "simulation/Contest.h"
#include "simulation/Engine.h"

#include <QTimer>

#include <algorithm>
#include <cmath>
#include <span>

namespace mr::audio {

namespace {

constexpr int kRenderIntervalMs = 4;   // ~250 Hz pacing; fills 8-slot
                                       // ring well ahead of audio.

}  // namespace

SimulationWorker::SimulationWorker(AudioRing& ring, QObject* parent)
    : QObject(parent), ring_(ring) {}

SimulationWorker::~SimulationWorker() {
    stop();
}

void SimulationWorker::start() {
    if (thread_) {
        return;
    }
    running_.store(true);
    thread_ = std::make_unique<QThread>();
    thread_->setObjectName(QStringLiteral("mr-sim"));
    moveToThread(thread_.get());
    connect(thread_.get(), &QThread::started, this, &SimulationWorker::onStarted);
    thread_->start(QThread::HighPriority);
}

void SimulationWorker::stop() {
    if (!thread_) {
        return;
    }
    running_.store(false);
    // Tear down the Contest on the sim thread before quitting so all
    // DSP destructors run on the thread that created them.
    QMetaObject::invokeMethod(this, [this]() {
        contest_.reset();
    }, Qt::BlockingQueuedConnection);
    thread_->quit();
    thread_->wait();
    thread_.reset();
}

void SimulationWorker::onStarted() {
    mr::core::setCurrentThreadName("mr-sim");
    qInfo(mrSim) << "SimulationWorker started";

    // Construct the Contest on the sim thread so its members live on
    // the right thread for the entire lifetime.
    // Try Master.dta first (Pascal CallLst.LoadCallList parity). The
    // file lives in the .app bundle's Resources/data — Qt resolves
    // that via applicationDirPath() going up from MacOS/. If the load
    // fails (file missing, format mismatch), fall back to the synthetic
    // HardcodedCallsignSource generator so Run still produces variety.
    std::unique_ptr<mr::sim::CallsignSource> calls;
    auto db = std::make_unique<mr::sim::CallsignDb>();
    const QString bundleDataDir =
        QFileInfo(QCoreApplication::applicationDirPath()
                  + QStringLiteral("/../Resources/data/Master.dta"))
            .absoluteFilePath();
    if (db->loadFromFile(bundleDataDir.toStdString())) {
        qInfo(mrSim) << "Master.dta loaded:" << db->size() << "calls from"
                     << bundleDataDir;
        calls = std::move(db);
    } else {
        qInfo(mrSim) << "Master.dta not found at" << bundleDataDir
                     << "— using synthetic callsign generator";
        calls = std::make_unique<mr::sim::HardcodedCallsignSource>();
    }
    contest_ = std::make_unique<mr::sim::Contest>(
        std::move(calls),
        mr::constants::Audio::kDefaultBufferSamples,
        mr::core::Random::instance());

    // Phase E: Contest starts in Stop mode. The Run menu / Run popup
    // button triggers setRunMode(PileUp/Single/Wpx/Hst) and the
    // engine starts producing audible content from that point on.
    contest_->setRunMode(mr::sim::RunMode::Stop);

    // Wire end-of-session: Contest reports the mode that just ended;
    // we re-emit on the GUI side for the score dialog. Phase E.G3
    // hooks the receiving slot.
    contest_->setEndOfSessionCallback([this](mr::sim::RunMode m) {
        emit contestEnded(static_cast<int>(m));
    });
    contest_->setQsoCompletedCallback(
        [this](const mr::sim::Contest::CompletedQso& q) {
            emit dxQsoCompleted(QString::fromStdString(q.call),
                                q.rst, q.nr, q.minute);
        });

    auto* timer = new QTimer(this);
    connect(timer, &QTimer::timeout, this, &SimulationWorker::renderTick);
    timer->start(kRenderIntervalMs);

    // E.G3: periodic GUI update emitter. 30 Hz keeps the clock and
    // qso/hr readouts responsive without flooding the main thread.
    // The signal's affinity is the sim thread, so Qt delivers it via
    // Qt::QueuedConnection to receivers on the GUI thread.
    auto* uiTimer = new QTimer(this);
    connect(uiTimer, &QTimer::timeout, this, [this]() {
        if (!contest_) {
            return;
        }
        const float minutes = contest_->currentMinute();
        const int seconds = static_cast<int>(std::lround(minutes * 60.0F));
        emit clockTicked(seconds);
    });
    uiTimer->start(33);
}

void SimulationWorker::renderTick() {
    if (!running_.load() || !contest_) {
        return;
    }
    while (running_.load()
           && ring_.size_approx() < mr::constants::Audio::kAudioRingFrames) {
        renderNextBlock();
    }
}

void SimulationWorker::renderNextBlock() {
    using mr::constants::Audio::kDefaultBufferSamples;

    AudioFrame out;
    out.n = static_cast<std::uint16_t>(kDefaultBufferSamples);
    out.blockIndex = framesProduced_.load(std::memory_order_relaxed);

    const std::size_t written = contest_->renderNextBlock(
        std::span<float>(out.samples.data(), kDefaultBufferSamples));
    if (written == 0) {
        std::fill_n(out.samples.data(), kDefaultBufferSamples, 0.0F);
    }

    ring_.try_enqueue(out);
    framesProduced_.fetch_add(1, std::memory_order_relaxed);
}

// ─── GUI-facing slots ────────────────────────────────────────────────
// Each slot edits the Contest's settings struct in place. The Contest
// reads a fresh copy at the top of every renderNextBlock, so changes
// take effect on the next audio block (~46 ms). We avoid locking by
// staying on the sim thread — every slot below is invoked via
// Qt::QueuedConnection from the GUI emitter.

namespace {

template <typename SettingMutator>
void mutateSettings(mr::sim::Contest* contest, SettingMutator&& m) {
    if (contest == nullptr) {
        return;
    }
    auto s = contest->settings();
    m(s);
    contest->setSettings(s);
}

}  // namespace

void SimulationWorker::setRunMode(int mode) {
    if (!contest_) {
        return;
    }
    contest_->setRunMode(static_cast<mr::sim::RunMode>(mode));
}

void SimulationWorker::sendPlayerMessage(int message) {
    if (!contest_) {
        return;
    }
    contest_->playerSendMessage(static_cast<mr::sim::Message>(message));
}

void SimulationWorker::setQrn(bool on) {
    mutateSettings(contest_.get(), [&](auto& s) { s.qrn = on; });
}
void SimulationWorker::setQrm(bool on) {
    mutateSettings(contest_.get(), [&](auto& s) { s.qrm = on; });
}
void SimulationWorker::setQsb(bool on) {
    mutateSettings(contest_.get(), [&](auto& s) { s.qsb = on; });
}
void SimulationWorker::setFlutter(bool on) {
    mutateSettings(contest_.get(), [&](auto& s) { s.flutter = on; });
}
void SimulationWorker::setLids(bool on) {
    mutateSettings(contest_.get(), [&](auto& s) { s.lids = on; });
}
void SimulationWorker::setQsk(bool on) {
    mutateSettings(contest_.get(), [&](auto& s) { s.qsk = on; });
}

void SimulationWorker::setWpm(int wpm) {
    mutateSettings(contest_.get(), [&](auto& s) { s.wpm = wpm; });
}
void SimulationWorker::setPitchHz(int hz) {
    mutateSettings(contest_.get(), [&](auto& s) { s.pitchHz = hz; });
}
void SimulationWorker::setBandwidthHz(int hz) {
    mutateSettings(contest_.get(), [&](auto& s) { s.rxBandwidthHz = hz; });
}
void SimulationWorker::setActivity(int activity) {
    mutateSettings(contest_.get(), [&](auto& s) { s.activity = activity; });
}
void SimulationWorker::setDurationMinutes(int minutes) {
    mutateSettings(contest_.get(),
                   [&](auto& s) { s.durationMinutes = minutes; });
}
void SimulationWorker::setRitHz(int hz) {
    mutateSettings(contest_.get(), [&](auto& s) { s.ritHz = hz; });
}
void SimulationWorker::setMonitorLevel(double normalisedValue) {
    mutateSettings(contest_.get(), [&](auto& s) {
        s.selfMonGain01 = static_cast<float>(normalisedValue);
    });
}
void SimulationWorker::setMyCallsign(const QString& call) {
    const std::string s = call.toStdString();
    mutateSettings(contest_.get(), [&](auto& cfg) { cfg.myCallsign = s; });
}

void SimulationWorker::setHeardCallsign(const QString& call) {
    // The "Call" entry field. F5 (HisCall) reads it directly; we
    // store it on the Contest's heardCall_ so MyStation's sendText
    // substitutes it for <his>.
    if (!contest_) {
        return;
    }
    contest_->setHeardCall(call.toStdString());
}

void SimulationWorker::abortSend() {
    if (!contest_) {
        return;
    }
    contest_->player().abortSend();
}

void SimulationWorker::setAudioRecording(bool on, const QString& path) {
    if (!contest_) {
        return;
    }
    if (on) {
        contest_->enableAudioRecording(path.toStdString());
    } else {
        contest_->disableAudioRecording();
    }
}

}  // namespace mr::audio
