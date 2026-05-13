// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "audio/AudioFrame.h"
#include "audio/AudioRing.h"
#include "core/Constants.h"

#include <gtest/gtest.h>

#include <atomic>
#include <thread>
#include <vector>

using mr::audio::AudioFrame;
using mr::audio::AudioRing;
using mr::audio::makeAudioRing;

TEST(AudioRing, SingleProducerSingleConsumer) {
    // Stress-test the SPSC primitive: one producer thread enqueues N
    // frames, one consumer thread dequeues; assert frame indices arrive
    // in order with no drops. Designed to be ThreadSanitizer-clean.
    AudioRing ring = makeAudioRing();

    constexpr std::uint64_t kCount = 100'000;
    std::atomic<bool> producerDone{false};
    std::atomic<std::uint64_t> consumed{0};
    std::uint64_t lastSeen = 0;

    std::thread producer([&] {
        for (std::uint64_t i = 0; i < kCount; ++i) {
            AudioFrame f;
            f.n = 1;
            f.samples[0] = static_cast<float>(i);
            f.blockIndex = i;
            while (!ring.try_enqueue(f)) {
                std::this_thread::yield();
            }
        }
        producerDone.store(true);
    });

    while (consumed.load() < kCount) {
        AudioFrame got;
        if (ring.try_dequeue(got)) {
            ASSERT_EQ(got.blockIndex, lastSeen) << "out-of-order frame";
            ++lastSeen;
            consumed.fetch_add(1);
        } else if (producerDone.load() && consumed.load() < kCount) {
            // Producer finished but a frame might still be in flight.
            std::this_thread::yield();
        } else {
            std::this_thread::yield();
        }
    }

    producer.join();
    EXPECT_EQ(consumed.load(), kCount);
}
