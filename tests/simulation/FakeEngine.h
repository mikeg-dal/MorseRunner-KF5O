// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Test-only fake of the Sim::Engine interface. Sets up enough state
// for Station / DxStation / DxOperator unit tests to drive the FSM
// without standing up a full Contest. Public fields are mutated by
// tests directly to script the scenario.

#pragma once

#include "core/Random.h"
#include "simulation/Engine.h"
#include "simulation/Messages.h"

#include <string>
#include <string_view>

namespace mr::sim::test {

class FakeEngine : public mr::sim::Engine {
public:
    explicit FakeEngine(std::uint64_t seed = 1) {
        rng_.reseed(seed);
    }

    [[nodiscard]] int currentBlockIndex() const noexcept override { return currentBlock_; }
    [[nodiscard]] float currentMinute() const noexcept override { return currentMinute_; }
    [[nodiscard]] std::string_view myCallsign() const override { return myCall_; }
    [[nodiscard]] std::string_view heardCallsign() const override { return heardCall_; }
    [[nodiscard]] const mr::sim::MessageSet& myLastMessage() const override { return lastMsg_; }
    [[nodiscard]] mr::sim::RunMode runMode() const noexcept override { return runMode_; }
    [[nodiscard]] bool lidsEnabled() const noexcept override { return lids_; }
    [[nodiscard]] bool flutterEnabled() const noexcept override { return flutter_; }
    [[nodiscard]] bool qsbEnabled() const noexcept override { return qsb_; }
    [[nodiscard]] int targetWpm() const noexcept override { return targetWpm_; }
    [[nodiscard]] int activity() const noexcept override { return activity_; }
    [[nodiscard]] int bufferSize() const noexcept override { return bufferSize_; }
    [[nodiscard]] mr::core::Random& random() override { return rng_; }

    // Fluent setters for use in tests.
    void setMyCall(std::string c) { myCall_ = std::move(c); }
    void setHeardCall(std::string c) { heardCall_ = std::move(c); }
    void setLastMessage(mr::sim::MessageSet s) { lastMsg_ = s; }
    void setLastMessage(std::initializer_list<mr::sim::Message> ms) {
        lastMsg_.reset();
        for (auto m : ms) {
            lastMsg_.set(static_cast<std::size_t>(m));
        }
    }
    void setRunMode(mr::sim::RunMode m) { runMode_ = m; }
    void setLids(bool on) { lids_ = on; }
    void setBlockIndex(int b) { currentBlock_ = b; }
    void setCurrentMinute(float m) { currentMinute_ = m; }

private:
    mr::core::Random& rng_ = mr::core::Random::instance();
    std::string myCall_ = "VE3NEA";
    std::string heardCall_;
    mr::sim::MessageSet lastMsg_{};
    mr::sim::RunMode runMode_ = mr::sim::RunMode::PileUp;
    bool lids_ = false;
    bool flutter_ = false;
    bool qsb_ = false;
    int targetWpm_ = 30;
    int activity_ = 3;
    int bufferSize_ = 512;
    int currentBlock_ = 0;
    float currentMinute_ = 0.0F;
};

}  // namespace mr::sim::test
