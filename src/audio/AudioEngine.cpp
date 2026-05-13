// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "audio/AudioEngine.h"

#include "core/Constants.h"
#include "core/Logging.h"
#include "core/ThreadNames.h"

#include <QAudioDevice>
#include <QMediaDevices>
#include <QTimer>

#include <algorithm>

namespace mr::audio {

namespace {

constexpr int kPumpIntervalMs = 8;  // ~125 Hz drain; smaller than one
                                    // 512-sample frame's playback time
                                    // (46 ms) so the ring rarely empties.

QAudioFormat makeFormat() {
    QAudioFormat fmt;
    fmt.setSampleRate(mr::constants::Audio::kSampleRate);
    fmt.setChannelCount(1);
    fmt.setSampleFormat(QAudioFormat::Float);  // matches our internal float pipeline
    return fmt;
}

}  // namespace

AudioEngine::AudioEngine(AudioRing& ring, QObject* parent)
    : QObject(parent), ring_(ring), format_(makeFormat()) {}

AudioEngine::~AudioEngine() {
    stop();
}

void AudioEngine::start() {
    if (thread_) {
        return;
    }

    thread_ = std::make_unique<QThread>();
    thread_->setObjectName(QStringLiteral("mr-audio"));
    // The QObject's worker context lives on `thread_`. We move ourselves
    // onto it so signals/slots from the timer marshal to that thread.
    moveToThread(thread_.get());

    connect(thread_.get(), &QThread::started, this, &AudioEngine::onWorkerStarted);
    connect(thread_.get(), &QThread::finished, this, &AudioEngine::onWorkerFinished,
            Qt::DirectConnection);

    thread_->start(QThread::TimeCriticalPriority);
}

void AudioEngine::stop() {
    if (!thread_) {
        return;
    }
    // Tear down on the audio thread itself so QAudioSink stays on the
    // thread that created it.
    QMetaObject::invokeMethod(this, [this]() {
        if (sink_) {
            sink_->stop();
            sink_.reset();
            device_ = nullptr;
        }
    }, Qt::BlockingQueuedConnection);
    thread_->quit();
    thread_->wait();
    thread_.reset();
}

void AudioEngine::onWorkerStarted() {
    mr::core::setCurrentThreadName("mr-audio");
    qInfo(mrAudio) << "AudioEngine worker started";

    const QAudioDevice device = QMediaDevices::defaultAudioOutput();
    if (device.isNull()) {
        qWarning(mrAudio) << "No default audio output device — engine inert";
        return;
    }
    if (!device.isFormatSupported(format_)) {
        qWarning(mrAudio) << "Default device does not support 11025 Hz mono float; "
                             "the host will resample.";
    }
    sink_ = std::make_unique<QAudioSink>(device, format_, this);

    // Buffer size in bytes: enough to hold a few default frames so a
    // short pump-thread stall doesn't underrun the host.
    constexpr int kSinkBufferBytes = mr::constants::Audio::kDefaultBufferSamples
                                     * sizeof(float)
                                     * 4;
    sink_->setBufferSize(kSinkBufferBytes);
    device_ = sink_->start();
    if (device_ == nullptr) {
        qWarning(mrAudio) << "QAudioSink::start returned null device";
        return;
    }

    // Drive the pump from a QTimer on the audio thread's own event
    // loop — keeps timing slop bounded and avoids busy-looping.
    auto* timer = new QTimer(this);
    connect(timer, &QTimer::timeout, this, &AudioEngine::pump);
    timer->start(kPumpIntervalMs);
}

void AudioEngine::onWorkerFinished() {
    qInfo(mrAudio) << "AudioEngine worker finished; underruns="
                   << underrunCount_.load()
                   << " frames=" << framesEmitted_.load();
}

void AudioEngine::pump() {
    if (device_ == nullptr) {
        return;
    }
    // Loop while the sink has any free space. Each iteration tries to
    // make forward progress on the in-flight frame; if it finishes, we
    // dequeue the next one and try again until either bytesFree drops
    // to zero or the producer hasn't supplied a new frame in time.
    //
    // The previous implementation dequeued a frame and then DROPPED IT
    // when bytes > bytesFree — which is the bug that caused the
    // staticky output during the Phase-B smoke test. We now hold the
    // in-flight frame as engine state and partial-write across ticks.
    while (true) {
        const qint64 free = sink_->bytesFree();
        if (free <= 0) {
            return;
        }

        if (!hasPending_) {
            if (!ring_.try_dequeue(pending_)) {
                // Producer hasn't filled a frame in time. Write a
                // short silence so the host's playback cursor keeps
                // moving — a brief silence is far preferable to a UI
                // freeze (which is what the original Delphi
                // `Synchronize` pattern produced).
                std::array<float, mr::constants::Audio::kDefaultBufferSamples> silence{};
                const qint64 wanted = std::min<qint64>(
                    static_cast<qint64>(silence.size() * sizeof(float)), free);
                device_->write(reinterpret_cast<const char*>(silence.data()), wanted);
                underrunCount_.fetch_add(1, std::memory_order_relaxed);
                return;
            }
            hasPending_ = true;
            pendingByteOffset_ = 0;
        }

        const std::size_t totalBytes =
            static_cast<std::size_t>(pending_.n) * sizeof(float);
        const std::size_t remaining = totalBytes - pendingByteOffset_;
        const qint64 toWrite =
            std::min<qint64>(static_cast<qint64>(remaining), free);
        if (toWrite <= 0) {
            return;
        }

        const auto* base = reinterpret_cast<const char*>(pending_.samples.data());
        const qint64 written = device_->write(base + pendingByteOffset_, toWrite);
        if (written <= 0) {
            // Backend declined the write even though bytesFree said
            // there was room. Bail until next tick rather than spin.
            return;
        }
        pendingByteOffset_ += static_cast<std::size_t>(written);

        if (pendingByteOffset_ >= totalBytes) {
            hasPending_ = false;
            pendingByteOffset_ = 0;
            framesEmitted_.fetch_add(1, std::memory_order_relaxed);
        }
    }
}

}  // namespace mr::audio
