// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AppKit
import MRAppCore
@testable import MorseRunner
import MRPersistence
import MRSimulation
import Testing

@MainActor
struct HostTests {
    @Test func appDoesNotStartUnderTests() {
        #expect(TestHost.isActive)
        // The delegate created no window and installed no menu.
        #expect(NSApp.windows.allSatisfy { !$0.isVisible })
        #expect(NSApp.activationPolicy() == .prohibited)
    }

    @Test func functionKeyConstantsMatchAppKit() {
        #expect(FunctionKey.upArrow == UInt32(NSUpArrowFunctionKey))
        #expect(FunctionKey.downArrow == UInt32(NSDownArrowFunctionKey))
        #expect(FunctionKey.f1 == UInt32(NSF1FunctionKey))
        #expect(FunctionKey.f8 == UInt32(NSF8FunctionKey))
        #expect(FunctionKey.f9 == UInt32(NSF9FunctionKey))
        #expect(FunctionKey.f10 == UInt32(NSF10FunctionKey))
        #expect(FunctionKey.f11 == UInt32(NSF11FunctionKey))
        #expect(FunctionKey.insert == UInt32(NSInsertFunctionKey))
        #expect(FunctionKey.help == UInt32(NSHelpFunctionKey))
        #expect(FunctionKey.pageUp == UInt32(NSPageUpFunctionKey))
        #expect(FunctionKey.pageDown == UInt32(NSPageDownFunctionKey))
    }

    @Test func tablesAgreeWithPersistenceLimits() {
        #expect(PitchTable.hz(index: 0) == Settings.Limits.pitchHz.lowerBound)
        #expect(PitchTable.hz(index: PitchTable.count - 1) == Settings.Limits.pitchHz.upperBound)
        #expect(PitchTable.hz(index: 1) - PitchTable.hz(index: 0) == Settings.Limits.pitchStepHz)
        #expect(BandwidthTable.hz(index: 0) == Settings.Limits.bandwidthHz.lowerBound)
        #expect(BandwidthTable.hz(index: BandwidthTable.count - 1) == Settings.Limits.bandwidthHz.upperBound)
        #expect(BandwidthTable.hz(index: 1) - BandwidthTable.hz(index: 0) == Settings.Limits.bandwidthStepHz)
        #expect(SpinRange.wpm.min...SpinRange.wpm.max == Settings.Limits.wpm)
        #expect(SpinRange.activity.min...SpinRange.activity.max == Settings.Limits.activity)
        #expect(SpinRange.duration.min == Settings.Limits.minDurationMinutes)
        #expect(SpeedStep.minWpm...SpeedStep.maxWpm == Settings.Limits.wpm)
        let d = UserSettings()
        #expect(PitchTable.hz(index: PitchTable.defaultIndex) == d.pitchHz)
        #expect(BandwidthTable.hz(index: BandwidthTable.defaultIndex) == d.bandwidthHz)
    }
}
