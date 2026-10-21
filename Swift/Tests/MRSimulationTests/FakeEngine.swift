// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Test-only fake of the Engine protocol (C++ tests/simulation/FakeEngine.h).
// Enough state for Station / DxStation / DxOperator unit tests to drive
// the FSM without standing up a full Contest.

import MRCore
@testable import MRSimulation

final class FakeEngine: Engine {
    let random: Random
    var currentBlockIndex = 0
    var currentMinute: Float = 0.0
    var myCallsign = "VE3NEA"
    var heardCallsign = ""
    var myLastMessage = MessageSet()
    var runMode: RunMode = .pileUp
    var lidsEnabled = false
    var flutterEnabled = false
    var qsbEnabled = false
    var targetWpm = 30
    var activity = 3
    var bufferSize = 512

    init(seed: UInt64 = 1) {
        random = Random(seed: seed)
    }

    func setLastMessage(_ ms: [Message]) {
        myLastMessage = MessageSet(ms)
    }
}
