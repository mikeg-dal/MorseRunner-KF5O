// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Owns the QAudioSink and the dedicated audio QThread. The audio
// thread runs an event loop and pulls AudioFrame from the SPSC ring on
// a periodic timer. **It never blocks** — if the producer (sim thread)
// falls behind, it writes silence and increments underrunCount_.
//
// The original Delphi build bounced audio buffer-fill callbacks through
// the GUI thread via `TWaitThread.Synchronize(ProcessEvent)`, which
// caused noticeable UI freezes under load. This class replaces that
// pattern: the sim thread renders ahead of time and the audio thread
// only marshals bytes to Core Audio.

#pragma once

#include "audio/AudioFrame.h"
#include "audio/AudioRing.h"

#include <QAudioFormat>
#include <QAudioSink>
#include <QIODevice>
#include <QObject>
#include <QThread>

#include <atomic>
#include <memory>

namespace mr::audio {

class AudioEngine : public QObject {
    Q_OBJECT
public:
    explicit AudioEngine(AudioRing& ring, QObject* parent = nullptr);
    ~AudioEngine() override;

    void start();
    void stop();

    [[nodiscard]] std::uint64_t underrunCount() const noexcept { return underrunCount_.load(); }
    [[nodiscard]] std::uint64_t framesEmitted() const noexcept { return framesEmitted_.load(); }

private slots:
    // Pulled from the audio thread's event loop. Drains as many frames
    // from the ring as the QAudioSink can absorb; on empty ring, writes
    // a silence frame and bumps underrunCount_.
    void pump();

private:
    void onWorkerStarted();
    void onWorkerFinished();

    AudioRing& ring_;
    std::unique_ptr<QThread> thread_;
    std::unique_ptr<QAudioSink> sink_;
    QIODevice* device_ = nullptr;  // owned by sink_; do not delete
    std::atomic<std::uint64_t> underrunCount_{0};
    std::atomic<std::uint64_t> framesEmitted_{0};
    QAudioFormat format_;

    // A frame can be dequeued from the SPSC ring but only partially
    // (or not at all) writable into QAudioSink this pump tick when the
    // host buffer is full. We hold the in-flight frame here, along
    // with a byte cursor into its samples, instead of discarding it.
    // This was the root cause of staticky output during smoke-testing —
    // the previous implementation re-dequeued every tick and dropped
    // any frame whose byte count exceeded `bytesFree`.
    AudioFrame pending_{};
    std::size_t pendingByteOffset_ = 0;
    bool hasPending_ = false;
};

}  // namespace mr::audio
