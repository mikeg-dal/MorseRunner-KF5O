// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

#include <QObject>

#include <memory>

namespace mr::ui {
class MainWindow;
}

namespace mr::audio {
class AudioEngine;
class SimulationWorker;
}

namespace mr::app {

// Owns the application-scoped objects and wires them together. Phase B
// adds AudioEngine + SimulationWorker (smoke-test producer) on their
// dedicated threads, exchanging AudioFrame via an SPSC ring buffer.
// Phase C replaces SimulationWorker with the real Contest engine; the
// threading topology is unchanged.
//
// The ring is held behind an opaque Impl pointer so the third-party
// SPSC queue type stays out of this header's reach.
class AppController : public QObject {
    Q_OBJECT
public:
    explicit AppController(QObject* parent = nullptr);
    ~AppController() override;

    void start();
    void shutdown();

private:
    struct Impl;
    std::unique_ptr<Impl> d_;
    std::unique_ptr<mr::ui::MainWindow> mainWindow_;
};

}  // namespace mr::app
