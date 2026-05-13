// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Lives on the sim thread (`mr-sim`). Owns the Sim::Contest, drives
// renderNextBlock at the configured audio cadence, and pushes
// AudioFrame instances into the SPSC ring buffer that AudioEngine
// drains on the audio thread.
//
// Phase E adds GUI-facing slots that the GUI thread invokes via
// QueuedConnection. Each slot trampolines onto the sim thread, mutates
// Contest in place, and returns. The Contest's renderNextBlock picks
// up the new settings on its next iteration.

#pragma once

#include "audio/AudioRing.h"
#include "simulation/Engine.h"
#include "simulation/Messages.h"

#include <QObject>
#include <QString>
#include <QThread>

#include <atomic>
#include <memory>

namespace mr::sim { class Contest; }

namespace mr::audio {

class SimulationWorker : public QObject {
    Q_OBJECT
public:
    explicit SimulationWorker(AudioRing& ring, QObject* parent = nullptr);
    ~SimulationWorker() override;

    void start();
    void stop();

    [[nodiscard]] std::uint64_t framesProduced() const noexcept {
        return framesProduced_.load();
    }

    // GUI-facing slots — connect to them via Qt::QueuedConnection so
    // the work always runs on the sim thread regardless of which
    // thread emitted the signal. All are no-ops if the Contest hasn't
    // been constructed yet (the GUI may emit during boot).

public slots:
    void setRunMode(int mode);                    // Sim::RunMode as int
    void sendPlayerMessage(int message);          // Sim::Message as int
    void setQrn(bool on);
    void setQrm(bool on);
    void setQsb(bool on);
    void setFlutter(bool on);
    void setLids(bool on);
    void setQsk(bool on);
    void setWpm(int wpm);
    void setPitchHz(int hz);
    void setBandwidthHz(int hz);
    void setActivity(int activity);
    void setDurationMinutes(int minutes);
    void setRitHz(int hz);
    void setMonitorLevel(double normalisedValue);
    void setMyCallsign(const QString& call);
    void setHeardCallsign(const QString& call);
    // E.G4 Esc: abort the player station's in-flight transmission.
    void abortSend();
    // Pascal File → Audio Recording Enabled. When `on` is true the
    // sim thread routes every rendered block into MorseRunner.wav.
    // `path` is the full destination; SimulationWorker resolves it
    // once on the GUI side via QStandardPaths::AppDataLocation.
    void setAudioRecording(bool on, const QString& path);

signals:
    // Sim-thread → GUI. The QObject's affinity is the sim thread, so
    // any receiver connected with Qt::AutoConnection (the default)
    // will see a QueuedConnection across the boundary. Phase E.G3
    // wires these to MainWindow slots.
    void clockTicked(int seconds);
    void rateUpdated(int qsoPerHour);
    void contestEnded(int mode);
    // E.G3 QSO truth back-fill. Fired on the sim thread when a
    // DxStation reaches Done; the GUI uses it to validate the Chk
    // column and update the score table.
    void dxQsoCompleted(const QString& call, int rst, int nr, float minute);

private slots:
    void renderTick();

private:
    void onStarted();
    void renderNextBlock();

    AudioRing& ring_;
    std::unique_ptr<QThread> thread_;
    std::atomic<bool> running_{false};
    std::atomic<std::uint64_t> framesProduced_{0};

    // Created on the sim thread inside onStarted() so all DSP state
    // is touched only by that thread.
    std::unique_ptr<mr::sim::Contest> contest_;
};

}  // namespace mr::audio
