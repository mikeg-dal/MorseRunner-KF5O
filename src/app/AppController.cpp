// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "app/AppController.h"

#include "audio/AudioEngine.h"
#include "audio/AudioRing.h"
#include "audio/SimulationWorker.h"
#include "core/Logging.h"
#include "core/ThreadNames.h"
#include "persistence/Settings.h"
#include "ui/MainWindow.h"
#include "ui/panels/BottomPanel.h"
#include "ui/panels/RightPanel.h"
#include "ui/widgets/RitSlider.h"
#include "ui/widgets/VolumeSlider.h"

#include <QCheckBox>
#include <QComboBox>
#include <QLineEdit>
#include <QObject>
#include <QSpinBox>

namespace mr::app {

// Implementation struct keeps the SPSC ring type (a moodycamel template
// instantiation) out of the public AppController.h. The engine and
// worker are also stored here so their destructors see complete types.
struct AppController::Impl {
    mr::audio::AudioRing ring;
    std::unique_ptr<mr::audio::AudioEngine> audioEngine;
    std::unique_ptr<mr::audio::SimulationWorker> simWorker;
    std::unique_ptr<mr::persistence::Settings> settings;

    Impl() : ring(mr::audio::makeAudioRing()) {}
};

AppController::AppController(QObject* parent)
    : QObject(parent), d_(std::make_unique<Impl>()) {
    // Name the main GUI thread for parity with mr-sim / mr-audio /
    // mr-wav / mr-dbload (visible in Instruments and `ps -M`).
    mr::core::setCurrentThreadName("mr-main");
}

AppController::~AppController() {
    shutdown();
}

void AppController::start() {
    qInfo(mrUi) << "AppController::start()";

    d_->settings = std::make_unique<mr::persistence::Settings>();
    const auto loaded = d_->settings->load();

    mainWindow_ = std::make_unique<mr::ui::MainWindow>();
    mainWindow_->show();

    // Bring up audio first (consumer). The producer would otherwise
    // immediately fill the ring and block on its cond-var.
    d_->audioEngine = std::make_unique<mr::audio::AudioEngine>(d_->ring);
    d_->audioEngine->start();

    d_->simWorker = std::make_unique<mr::audio::SimulationWorker>(d_->ring);
    d_->simWorker->start();

    // Phase-E.G1 wiring: route MainWindow signals to SimulationWorker
    // slots via Qt::QueuedConnection. The Worker's QObject affinity is
    // the sim thread, so QueuedConnection is mandatory here.
    auto* mw = mainWindow_.get();
    auto* sw = d_->simWorker.get();
    connect(mw, &mr::ui::MainWindow::runModeRequested,     sw,
            &mr::audio::SimulationWorker::setRunMode, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::stopRequested,        sw,
            &mr::audio::SimulationWorker::requestStop, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::sendMessageRequested, sw,
            &mr::audio::SimulationWorker::sendPlayerMessage, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::playerCallEdited,     sw,
            &mr::audio::SimulationWorker::playerEditedCall, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::qsoLogged,            sw,
            &mr::audio::SimulationWorker::logQso, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::qrnToggled,           sw,
            &mr::audio::SimulationWorker::setQrn, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::qrmToggled,           sw,
            &mr::audio::SimulationWorker::setQrm, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::qsbToggled,           sw,
            &mr::audio::SimulationWorker::setQsb, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::flutterToggled,       sw,
            &mr::audio::SimulationWorker::setFlutter, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::lidsToggled,          sw,
            &mr::audio::SimulationWorker::setLids, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::qskToggled,           sw,
            &mr::audio::SimulationWorker::setQsk, Qt::QueuedConnection);

    // E.G2 numeric settings.
    connect(mw, &mr::ui::MainWindow::wpmChanged,           sw,
            &mr::audio::SimulationWorker::setWpm, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::pitchChanged,         sw,
            &mr::audio::SimulationWorker::setPitchHz, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::bandwidthChanged,     sw,
            &mr::audio::SimulationWorker::setBandwidthHz, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::activityChanged,      sw,
            &mr::audio::SimulationWorker::setActivity, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::durationChanged,      sw,
            &mr::audio::SimulationWorker::setDurationMinutes, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::monitorLevelChanged,  sw,
            &mr::audio::SimulationWorker::setMonitorLevel, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::myCallsignChanged,    sw,
            &mr::audio::SimulationWorker::setMyCallsign, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::ritChanged,           sw,
            &mr::audio::SimulationWorker::setRitHz, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::abortSendRequested,   sw,
            &mr::audio::SimulationWorker::abortSend, Qt::QueuedConnection);
    connect(mw, &mr::ui::MainWindow::audioRecordingToggled, sw,
            &mr::audio::SimulationWorker::setAudioRecording,
            Qt::QueuedConnection);

    // E.G3 reverse direction: sim → GUI. Both signals are emitted on
    // the sim thread, so AutoConnection resolves to QueuedConnection
    // for receivers on the GUI thread.
    connect(sw, &mr::audio::SimulationWorker::clockTicked,
            mw, &mr::ui::MainWindow::onClockTicked);
    connect(sw, &mr::audio::SimulationWorker::contestEnded,
            mw, &mr::ui::MainWindow::onContestEnded);
    connect(sw, &mr::audio::SimulationWorker::dxQsoCompleted,
            mw, &mr::ui::MainWindow::onDxQsoCompleted);
    connect(sw, &mr::audio::SimulationWorker::playerPieceFinished,
            mw, &mr::ui::MainWindow::onPlayerPieceFinished);
    connect(sw, &mr::audio::SimulationWorker::callEditResult,
            mw, &mr::ui::MainWindow::onCallEditResult);
    connect(sw, &mr::audio::SimulationWorker::sendAborted,
            mw, &mr::ui::MainWindow::onSendAborted);

    // E.G4: persist every control change to the plist on the spot.
    // Settings::set*() calls sync() so the value is flushed even if the
    // app crashes immediately afterwards. The same MainWindow signals
    // already drive the sim worker, so the persist + apply paths run
    // in parallel from the GUI thread.
    auto* st = d_->settings.get();
    connect(mw, &mr::ui::MainWindow::myCallsignChanged,
            this, [st](const QString& v) { st->setMyCallsign(v); });
    connect(mw, &mr::ui::MainWindow::wpmChanged,
            this, [st](int v) { st->setWpm(v); });
    connect(mw, &mr::ui::MainWindow::pitchChanged,
            this, [st](int v) { st->setPitchHz(v); });
    connect(mw, &mr::ui::MainWindow::bandwidthChanged,
            this, [st](int v) { st->setBandwidthHz(v); });
    connect(mw, &mr::ui::MainWindow::activityChanged,
            this, [st](int v) { st->setActivity(v); });
    connect(mw, &mr::ui::MainWindow::durationChanged,
            this, [st](int v) { st->setDurationMinutes(v); });
    connect(mw, &mr::ui::MainWindow::monitorLevelChanged,
            this, [st](double v) { st->setMonitorLevel(v); });
    connect(mw, &mr::ui::MainWindow::qskToggled,
            this, [st](bool v) { st->setQsk(v); });
    connect(mw, &mr::ui::MainWindow::qrnToggled,
            this, [st](bool v) { st->setQrn(v); });
    connect(mw, &mr::ui::MainWindow::qrmToggled,
            this, [st](bool v) { st->setQrm(v); });
    connect(mw, &mr::ui::MainWindow::qsbToggled,
            this, [st](bool v) { st->setQsb(v); });
    connect(mw, &mr::ui::MainWindow::flutterToggled,
            this, [st](bool v) { st->setFlutter(v); });
    connect(mw, &mr::ui::MainWindow::lidsToggled,
            this, [st](bool v) { st->setLids(v); });
    // Persist Audio Recording Enabled. We capture only `on` — the
    // resolved path is recomputed each launch from QStandardPaths so
    // moving the bundle across machines still finds a valid location.
    connect(mw, &mr::ui::MainWindow::audioRecordingToggled,
            this, [st](bool on, const QString&) { st->setSaveWav(on); });

    // Apply loaded settings AFTER every signal connection above is in
    // place. The setChecked / setValue / setText calls emit the
    // matching change signal, which now propagates both to the sim
    // worker (effects take hold) AND to the persistence layer (keeps
    // the plist in sync with the actual sim state). Doing this before
    // the connections existed was the bug — the controls flipped
    // visually but nobody was listening, so the sim kept its
    // hard-coded defaults and the plist stayed in sync with those.
    if (auto* rp = mainWindow_->rightPanel(); rp != nullptr) {
        rp->callEdit()->setText(loaded.myCallsign);
        rp->wpmSpin()->setValue(loaded.wpm);
        rp->qskCheckBox()->setChecked(loaded.qsk);
        rp->qrnCheckBox()->setChecked(loaded.qrn);
        rp->qrmCheckBox()->setChecked(loaded.qrm);
        rp->qsbCheckBox()->setChecked(loaded.qsb);
        rp->flutterCheckBox()->setChecked(loaded.flutter);
        rp->lidsCheckBox()->setChecked(loaded.lids);
        rp->activitySpin()->setValue(loaded.activity);
        rp->durationSpin()->setValue(loaded.durationMinutes);
        // Items read "600 Hz" with the bare Hz value as item data, so
        // match on data — setCurrentText("600") never finds an item.
        if (const int i = rp->pitchCombo()->findData(loaded.pitchHz); i >= 0) {
            rp->pitchCombo()->setCurrentIndex(i);
        }
        if (const int i = rp->bandwidthCombo()->findData(loaded.bandwidthHz); i >= 0) {
            rp->bandwidthCombo()->setCurrentIndex(i);
        }
        if (auto* vs = rp->volumeSlider(); vs != nullptr) {
            vs->setValue(loaded.monitorLevel);
        }
    }
    // Pascal never persists RIT; it starts at 0 every launch.

    // INI-only options.
    mainWindow_->setCompetitionDuration(loaded.competitionDuration);
    QMetaObject::invokeMethod(sw, [sw, on = loaded.callsFromKeyer]() {
        sw->setCallsFromKeyer(on);
    }, Qt::QueuedConnection);
    // Restore the operator name in the title bar (Pascal Operator1Click
    // also re-applies on next startup via FormCreate).
    mainWindow_->applyHamNameToTitle(loaded.hamName);

    // Restore Audio Recording Enabled. The setChecked call here fires
    // the toggle handler we wired above, which both forwards to the
    // sim worker (now connected) and re-persists. We could suppress
    // the persist round-trip with a QSignalBlocker but it's harmless.
    if (auto* a = mainWindow_->audioRecordingAction(); a != nullptr) {
        a->setChecked(loaded.saveWav);
    }
}

void AppController::shutdown() {
    if (!d_) {
        return;
    }
    if (d_->simWorker) {
        d_->simWorker->stop();
        d_->simWorker.reset();
    }
    if (d_->audioEngine) {
        d_->audioEngine->stop();
        d_->audioEngine.reset();
    }
    mainWindow_.reset();
}

}  // namespace mr::app
