// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

@testable import MRAppCore
import MRSimulation
import Testing

extension RunMode: CustomTestStringConvertible {
    public var testDescription: String { RunModeRules.title(self).isEmpty ? "Stop" : RunModeRules.title(self) }
}

private let allModes: [RunMode] = [.stop, .pileUp, .single, .wpx, .hst]

struct RunModeRulesTests {
    @Test(arguments: allModes)
    func matrix(_ m: RunMode) {
        let c = RunModeRules.controls(for: m, competitionDuration: 60)
        let stop = m == .stop, compet = m == .wpx || m == .hst, hst = m == .hst
        #expect(c.mode == m)
        #expect(c.myCallEnabled == stop)
        #expect(c.durationEnabled == stop)
        #expect(c.runButtonDown == !stop)
        #expect(c.runItemsEnabled == stop)
        #expect(c.stopEnabled == !stop)
        #expect(c.conditionsEnabled == !compet)
        #expect(c.activityEnabled == !hst)
        #expect(c.bandwidthEnabled == !hst)
        #expect(c.resetsSession == !stop)
        #expect(c.recording == (stop ? .close : .openIfEnabled))
        #expect(c.captionColor == (compet ? .red : .green))
    }

    @Test(arguments: [
        (RunMode.stop, nil as Bool?, nil as Int?, nil as Int?, nil as Int?, nil as Bool?, ""),
        (RunMode.pileUp, nil, nil, nil, nil, true, "Pile-Up"),
        (RunMode.single, nil, nil, nil, nil, true, "Single Calls"),
        (RunMode.wpx, true, 45, nil, nil, true, "COMPETITION"),
        (RunMode.hst, false, 45, 4, 10, false, "H S T"),
    ])
    func forcedValues(_ m: RunMode, _ cond: Bool?, _ dur: Int?, _ act: Int?, _ bw: Int?,
                      _ table: Bool?, _ caption: String) {
        let c = RunModeRules.controls(for: m, competitionDuration: 45)
        #expect(c.forcedConditions == cond)
        #expect(c.forcedDuration == dur)
        #expect(c.forcedActivity == act)
        #expect(c.forcedBandwidthIndex == bw)
        #expect(c.scoreTableVisible == table)
        #expect(c.caption == caption)
    }

    @Test func hstBandwidthIs600() throws {
        let i = try #require(RunModeRules.controls(for: .hst, competitionDuration: 60).forcedBandwidthIndex)
        #expect(BandwidthTable.hz(index: i) == 600)
    }

    @Test(arguments: allModes)
    func runSameModeIsANoOp(_ m: RunMode) {
        #expect(!RunModeRules.shouldRun(m, current: m))
        for other in allModes where other != m {
            #expect(RunModeRules.shouldRun(other, current: m))
        }
    }
}

struct KeyCase: Sendable, CustomTestStringConvertible {
    let key: UInt32
    let chars: String
    let mods: KeyModifiers
    let expected: KeyCommand?
    let name: String
    var testDescription: String { name }

    init(_ name: String, _ key: UInt32, _ expected: KeyCommand?, chars: String? = nil,
         mods: KeyModifiers = []) {
        self.name = name
        self.key = key
        self.chars = chars ?? (Unicode.Scalar(key).map { String(Character($0)) } ?? "")
        self.mods = mods
        self.expected = expected
    }
}

private func ch(_ c: Character) -> UInt32 { c.unicodeScalars.first!.value }

struct KeyCommandTests {
    @Test(arguments: [
        KeyCase("Insert", FunctionKey.insert, .hisCallAndNr),
        KeyCase("Help (Insert position)", FunctionKey.help, .hisCallAndNr),
        KeyCase("Return", 13, .enter(forceSave: false)),
        KeyCase("keypad Enter", 3, .enter(forceSave: false)),
        KeyCase("Shift-Return", 13, .enter(forceSave: true), mods: .shift),
        KeyCase("Ctrl-Return", 13, .enter(forceSave: true), mods: .control),
        KeyCase("Cmd-Return", 13, .enter(forceSave: true), mods: .command),
        KeyCase("Alt-Return", 13, .enter(forceSave: true), mods: .option),
        KeyCase("F11", FunctionKey.f11, .wipe),
        KeyCase("Alt-W", ch("w"), .wipe, chars: "∑", mods: .option),
        KeyCase("Ctrl-W", ch("w"), .wipe, chars: "\u{17}", mods: .control),
        KeyCase("Cmd-W", ch("w"), .wipe, chars: "w", mods: .command),
        KeyCase("Alt-Shift-W", ch("W"), .wipe, chars: "„", mods: [.option, .shift]),
        KeyCase("plain w", ch("w"), nil, chars: "w"),
        KeyCase("Up", FunctionKey.upArrow, .rit(1)),
        KeyCase("Down", FunctionKey.downArrow, .rit(-1)),
        KeyCase("Ctrl-Up", FunctionKey.upArrow, .bandwidth(1), mods: .control),
        KeyCase("Cmd-Down", FunctionKey.downArrow, .bandwidth(-1), mods: .command),
        KeyCase("PgUp", FunctionKey.pageUp, .speedUp),
        KeyCase("PgDn", FunctionKey.pageDown, .speedDown),
        KeyCase("F9", FunctionKey.f9, .ignore),
        KeyCase("F10", FunctionKey.f10, .ignore),
        KeyCase("Alt-F9", FunctionKey.f9, .speedDown, mods: .option),
        KeyCase("Ctrl-F10", FunctionKey.f10, .speedUp, mods: .control),
        KeyCase("Cmd-F10", FunctionKey.f10, .speedUp, mods: .command),
        KeyCase("Esc", 27, .abort),
        KeyCase(";", ch(";"), .hisCallAndNr),
        KeyCase(".", ch("."), .tuAndSave),
        KeyCase("+", ch("+"), .tuAndSave),
        KeyCase("[", ch("["), .tuAndSave),
        KeyCase(",", ch(","), .tuAndSave),
        KeyCase("Space", ch(" "), .space),
        KeyCase("backslash", ch("\\"), .cq),
        KeyCase("letter", ch("a"), nil),
        KeyCase("digit", ch("5"), nil),
        KeyCase("Cmd-Q", ch("q"), nil, chars: "q", mods: .command),
        KeyCase("Cmd-.", ch("."), nil, chars: ".", mods: .command),
        KeyCase("Ctrl-;", ch(";"), nil, chars: ";", mods: .control),
        KeyCase("Alt-Space", ch(" "), nil, chars: " ", mods: .option),
        KeyCase("F1 goes to the menu", FunctionKey.f(1), nil),
        KeyCase("F8 goes to the menu", FunctionKey.f8, nil),
    ])
    func map(_ k: KeyCase) {
        #expect(KeyCommand.map(key: k.key, characters: k.chars, modifiers: k.mods) == k.expected)
    }

    @Test func shiftedPunctuationTypesThroughCharacters() {
        // '+' is Shift-'=' on US keyboards: FormKeyPress sees '+'.
        #expect(KeyCommand.map(key: ch("="), characters: "+", modifiers: .shift) == .tuAndSave)
    }

    @Test func modifierRule() {
        #expect(KeyModifiers.command.ctrl)
        #expect(KeyModifiers.control.ctrl)
        #expect(!KeyModifiers.option.ctrl)
        #expect(KeyModifiers.option.alt)
        #expect(!KeyModifiers.shift.ctrl && !KeyModifiers.shift.alt)
    }

    @Test func functionKeys() {
        #expect(FunctionKey.f(1) == FunctionKey.f1)
        #expect(FunctionKey.f(8) == FunctionKey.f8)
        #expect(FunctionKey.f(9) == FunctionKey.f9)
        #expect(FunctionKey.f(11) == FunctionKey.f11)
    }
}
