// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

@testable import MRAppCore
import Testing

struct MonitorLevelTests {
    @Test(arguments: [
        // VolumeSlider1Change: Value' = 80(Value − 0.75)/60 + 1, clamped.
        (Float(0.75), Float(1.0)), (Float(0.0), Float(0.0)), (Float(1.0), Float(1.0)),
        (Float(0.6), Float(0.8)), (Float(0.5), Float(2.0 / 3.0)), (Float(0.3), Float(0.4)),
    ])
    func mainFormRemap(_ v: Float, _ expected: Float) {
        #expect(abs(MonitorLevel.afterMainFormChange(v) - expected) < 1e-6)
    }

    @Test(arguments: [
        // SelfMonClick: Value := Tag/80 + 0.75, then the remap.
        (-60, Float(0.0)), (-40, Float(1.0 / 3.0)), (-20, Float(2.0 / 3.0)), (0, Float(1.0)), (20, Float(1.0)),
    ])
    func menuLevels(_ tag: Int, _ expected: Float) {
        #expect(abs(MonitorLevel.menuValue(tag: tag) - expected) < 1e-6)
    }

    @Test func doubleClickGoesThroughTheRemap() {
        // Value := 0.75; OnChange → Db := 0 → Value 1.
        #expect(MonitorLevel.doubleClickValue == 1)
    }

    @Test(arguments: [Float(-1), Float(-0.001), Float(0), Float(0.5), Float(1), Float(1.5), Float.nan])
    func clamp(_ v: Float) {
        let c = MonitorLevel.clamp(v)
        #expect(c >= 0 && c <= 1)
        if v >= 0, v <= 1 { #expect(c == v) }
    }

    @Test func dbMapping() {
        #expect(MonitorLevel.db(value: 1) == 0)
        #expect(MonitorLevel.db(value: 0.75) == -15)
        #expect(MonitorLevel.db(value: 0) == -60)
        #expect(MonitorLevel.value(db: -15) == 0.75)
        #expect(MonitorLevel.value(db: 30) == 1)
        #expect(MonitorLevel.value(db: -90) == 0)
    }

    @Test(arguments: [
        (Float(0.75), "-15.0 dB"), (Float(1), "0.0 dB"), (Float(0), "-60.0 dB"),
    ])
    func sliderHint(_ v: Float, _ text: String) {
        #expect(MonitorLevel.sliderHint(value: v) == text)
    }

    @Test(arguments: [
        (Float(1), "0 dB"), (Float(0), "-60 dB"), (Float(2.0 / 3.0), "-20 dB"),
        // Delphi Format('%.0f', [-0.4]) prints "-0", as printf does.
        (Float(1 - 0.4 / 60), "-0 dB"),
    ])
    func mainFormHint(_ v: Float, _ text: String) {
        #expect(MonitorLevel.mainFormHint(value: v) == text)
    }

    @Test func dragUsesTheDownValue() {
        // Width 60, margin 5: 50 px = full scale. +10 px from 0.5 = 0.7.
        let v = MonitorLevel.dragValue(downValue: 0.5, deltaX: 10, width: 60)
        #expect(abs(v - MonitorLevel.afterMainFormChange(0.7)) < 1e-6)
        #expect(MonitorLevel.dragValue(downValue: 0.5, deltaX: -1000, width: 60) == 0)
        #expect(MonitorLevel.dragValue(downValue: 0.5, deltaX: 1000, width: 60) == 1)
        // Degenerate width: no division by zero.
        #expect(MonitorLevel.dragValue(downValue: 0.75, deltaX: 3, width: 10) == 1)
    }

    @Test func thumbGeometry() {
        // x = 5 + Round(50·0.75) = 5 + Round(37.5) = 5 + 38 (banker's: 38).
        #expect(MonitorLevel.thumbCenterX(value: 0.75, width: 60) == 43)
        #expect(MonitorLevel.thumbCenterX(value: 0.25, width: 60) == 17)  // Round(12.5) = 12
        let r = MonitorLevel.thumbRect(value: 0, width: 60, height: 20)
        #expect(r.x == 1 && r.y == 3 && r.width == 9 && r.height == 15)
        #expect(MonitorLevel.hitsThumb(x: 1, y: 3, value: 0, width: 60, height: 20))
        #expect(!MonitorLevel.hitsThumb(x: 10, y: 3, value: 0, width: 60, height: 20))
        #expect(!MonitorLevel.hitsThumb(x: 5, y: 18, value: 0, width: 60, height: 20))
    }

    @Test(arguments: [(Float(0.75), 0), (Float(1), 20), (Float(0), -60), (Float(0.5), -20)])
    func iniInteger(_ v: Float, _ i: Int) {
        #expect(MonitorLevel.iniInteger(value: v) == i)
    }
}

struct TableTests {
    @Test func pitch() {
        #expect(PitchTable.count == 13)
        #expect(PitchTable.titles.first == "300 Hz")
        #expect(PitchTable.titles.last == "900 Hz")
        for i in 0..<PitchTable.count {
            #expect(PitchTable.index(hz: PitchTable.hz(index: i)) == i)
        }
        #expect(PitchTable.index(hz: 475) == nil)
        #expect(PitchTable.index(hz: 950) == nil)
        #expect(PitchTable.index(hz: 250) == nil)
        #expect(PitchTable.clampedIndex(-3) == 0)
        #expect(PitchTable.clampedIndex(99) == 12)
        #expect(PitchTable.hz(index: PitchTable.defaultIndex) == 450)
    }

    @Test func bandwidth() {
        #expect(BandwidthTable.count == 11)
        #expect(BandwidthTable.titles == (0..<11).map { "\(100 + $0 * 50) Hz" })
        #expect(BandwidthTable.hz(index: BandwidthTable.hstIndex) == 600)
        #expect(BandwidthTable.hz(index: BandwidthTable.defaultIndex) == 550)
        #expect(BandwidthTable.isValid(index: 0) && BandwidthTable.isValid(index: 10))
        #expect(!BandwidthTable.isValid(index: -1) && !BandwidthTable.isValid(index: 11))
    }

    @Test(arguments: [(500, 8), (100, 0), (600, 10), (550, 9), (650, 9), (525, 9), (0, 9), (-50, 9)])
    func storedBandwidth(_ hz: Int, _ index: Int) {
        #expect(BandwidthTable.index(storedHz: hz) == index)
    }

    @Test(arguments: [
        (30, 35, 25), (32, 35, 30), (10, 15, 10), (12, 15, 10), (120, 120, 115),
        (118, 120, 115), (9, 10, 10), (5, 10, 10), (200, 120, 120),
    ])
    func speedSteps(_ wpm: Int, _ up: Int, _ down: Int) {
        #expect(SpeedStep.up(wpm) == up)
        #expect(SpeedStep.down(wpm) == down)
    }

    @Test(arguments: [
        (SpinRange.wpm, 10, 120, 3), (SpinRange.activity, 1, 9, 1), (SpinRange.duration, 1, 240, 3),
    ])
    func spinRanges(_ r: SpinRange, _ lo: Int, _ hi: Int, _ len: Int) {
        #expect(r.min == lo && r.max == hi && r.maxLength == len)
        // Every value in range is typable within maxLength.
        #expect(String(hi).count <= r.maxLength)
    }

    @Test func spinTypedValues() {
        let r = SpinRange.wpm
        #expect(r.typedValue("1") == nil)      // not yet in range
        #expect(r.typedValue("15") == 15)
        #expect(r.typedValue("") == nil)
        #expect(r.typedValue("121") == nil)
        #expect(r.committedValue("1", current: 30) == 10)
        #expect(r.committedValue("999", current: 30) == 120)
        #expect(r.committedValue("", current: 30) == 30)
        #expect(r.committedValue("x", current: 42) == 42)
        #expect(SpinRange.duration.committedValue("240", current: 30) == 240)
    }

    @Test(arguments: [
        (0, 1, 50), (0, -1, -50), (450, 1, 500), (500, 1, 500), (-500, -1, -500),
        (300, 0, 0), (-250, 0, 0),
    ])
    func ritStep(_ rit: Int, _ d: Int, _ expected: Int) {
        #expect(Rit.step(rit, by: d) == expected)
    }

    @Test(arguments: [
        // (start, dx px, expected): 9 Hz per px, snapped to 50, ±500.
        (0, 0.0, 0), (0, 2.0, 0), (0, 3.0, 50), (0, -3.0, -50), (0, 5.6, 50),
        (0, 11.0, 100), (100, -11.0, 0), (0, 100.0, 500), (0, -100.0, -500),
        (450, 6.0, 500), (-500, 1.0, -500), (-500, 3.0, -450),
    ])
    func ritDrag(_ start: Int, _ dx: Double, _ expected: Int) {
        #expect(Rit.dragged(from: start, dx: dx) == expected)
    }

    @Test func ritDragLandsOnTheStepGrid() {
        for dx in stride(from: -80.0, through: 80.0, by: 0.5) {
            let hz = Rit.dragged(from: 0, dx: dx)
            #expect(hz % Rit.stepHz == 0 && abs(hz) <= Rit.limitHz)
        }
    }

    @Test func ritMarker() {
        // Panel8 225 × 9, 500 Hz: Width 55, Left (225 − 55) div 2 = 85.
        let m = Rit.marker(panelWidth: 225, panelHeight: 9, bandwidthHz: 500, ritHz: 0)
        #expect(m.x == 85 && m.y == 1 && m.width == 55 && m.height == 7)
        // Rit div 9 truncates toward zero: −50 div 9 = −5.
        #expect(Rit.marker(panelWidth: 225, panelHeight: 9, bandwidthHz: 500, ritHz: -50).x == 80)
        #expect(Rit.marker(panelWidth: 225, panelHeight: 9, bandwidthHz: 500, ritHz: 50).x == 90)
    }

    @Test(arguments: [
        (10, 4, -1 as Int?), (84, 4, -1), (85, 4, 0), (139, 4, 0), (140, 4, nil), (141, 4, 1),
        (200, 4, 1), (100, 0, nil), (100, 8, nil), (100, 1, 0), (100, 7, 0),
    ])
    func ritHit(_ x: Int, _ y: Int, _ expected: Int?) {
        #expect(Rit.hit(x: x, y: y, panelWidth: 225, panelHeight: 9, bandwidthHz: 500, ritHz: 0)
                == expected)
    }
}
