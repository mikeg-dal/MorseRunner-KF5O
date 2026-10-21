// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
@testable import MRAppCore
import MRScoring
import MRSimulation
import Testing

struct CaptionTests {
    @Test(arguments: [
        (0.0, "00:00:00"), (59.4994, "00:00:59"), (59.9996, "00:01:00"), (3_599.0, "00:59:59"),
        (3_600.0, "01:00:00"), (86_399.0, "23:59:59"), (86_400.0, "00:00:00"), (90_061.0, "01:01:01"),
        (-1.0, "00:00:00"), (Double.nan, "00:00:00"),
    ])
    func clock(_ s: Double, _ text: String) {
        #expect(Captions.clock(seconds: s) == text)
    }

    @Test func smallCaptions() {
        #expect(Captions.rate(0) == "0  qso/hr.")
        #expect(Captions.rate(123) == "123  qso/hr.")
        #expect(Captions.pileUp(3) == "Pile-Up:  3")
        #expect(Captions.windowTitle(hamName: "") == "Morse Runner")
        #expect(Captions.windowTitle(hamName: "Mike") == "Morse Runner:  Mike")
    }

    @Test func headers() {
        #expect(Captions.logHeader(hst: false).hasSuffix("Pref   Chk"))
        #expect(Captions.logHeader(hst: true).hasSuffix("Score  Chk"))
        #expect(Captions.logHeader(hst: false).count == Captions.logHeader(hst: true).count)
    }

    @Test func logRowSplit() throws {
        var log = QsoLog()
        log.add(t: 61, call: "K1ABC", rst: 599, nr: 5, hstMode: false)
        let row = log.formatRow(0, sentRst: 599)
        let (body, tag) = Captions.splitLogRow(row)
        #expect(tag == "NIL")
        #expect(body + tag == row)
        #expect(body.hasPrefix(" 00:01:01  K1ABC"))
    }

    @Test(arguments: [
        (nil as String?, "Your score table is empty"),
        ("", ""),
        ("a\nb\n", "a\nb"),
        ("a\r\nb\r\n", "a\r\nb"),
        ("one", "one"),
    ])
    func scoreTableText(_ file: String?, _ shown: String) {
        #expect(Captions.scoreTableText(fileContents: file) == shown)
    }
}

struct ScoreTableModelTests {
    private func stats(rawPts: Int = 0, rawMul: Int = 0, rawScore: Int, verPts: Int = 0, verMul: Int = 0,
                       verScore: Int) -> Stats {
        var s = Stats()
        s.raw = ScoreRow(pts: rawPts, mul: rawMul, score: rawScore)
        s.verified = ScoreRow(pts: verPts, mul: verMul, score: verScore)
        return s
    }

    @Test func resetByMode() {
        var m = ScoreTableModel()
        m.reset(hst: true)
        #expect(m.cells == [["", ""], ["", ""], ["0", "0"]])
        m.reset(hst: false)
        #expect(m.cells == [["0", "0"], ["0", "0"], ["0", "0"]])
    }

    @Test func hstCaptionResetsOnANewRun() {
        var m = ScoreTableModel()
        m.reset(hst: true)
        m.update(stats(rawScore: 40, verScore: 33), hst: true)
        #expect(m.hstCaption == "33")
        m.reset(hst: true)
        #expect(m.hstCaption == "0")
    }

    @Test func updates() {
        var m = ScoreTableModel()
        m.update(stats(rawPts: 3, rawMul: 2, rawScore: 6, verPts: 2, verMul: 1, verScore: 2), hst: false)
        #expect(m.cells == [["3", "2"], ["2", "1"], ["6", "2"]])
        #expect(m.verifiedPts == "2" && m.verifiedMul == "1" && m.verifiedScore == "2")
        #expect(m.hstCaption == "0")  // WPX leaves Panel11 alone
        m.update(stats(rawScore: 10, verScore: 7), hst: true)
        #expect(m.cells == [["", ""], ["", ""], ["10", "7"]])
        #expect(m.hstCaption == "7")
    }

    @Test func titles() {
        #expect(ScoreTableModel.rowTitles == ["Pts", "Mult", "Score"])
        #expect(ScoreTableModel.columnTitles == ["", "Raw", "Verified"])
    }
}

struct HistogramGeometryTests {
    @Test func binsFollowQsoLog() {
        #expect(HistogramGeometry.binCount == QsoLog.histogramBins)
        #expect(HistogramGeometry.emptyBins.count == QsoLog.histogramBins)
    }

    @Test(arguments: [(0, 0, 1, 56, 1), (1, 0, 5, 56, 1), (47, 3, 189, 50, 7), (2, 10, 9, 36, 21)])
    func bar(_ i: Int, _ n: Int, _ x: Int, _ y: Int, _ h: Int) {
        // PaintBox1 223 × 59.
        let b = HistogramGeometry.bar(index: i, count: n, height: 59)
        #expect(b.x == x && b.y == y && b.width == 3 && b.height == h)
    }

    @Test func allBarsFitTheBox() {
        let bars = HistogramGeometry.bars(HistogramGeometry.emptyBins, height: 59)
        #expect(bars.count == 48)
        #expect(bars.allSatisfy { $0.x + $0.width <= 223 })
    }
}

struct ContestEndTests {
    // 2026-03-04 05:06:07 UTC.
    private let now = Date(timeIntervalSince1970: 1_772_600_767)
    private let utc = TimeZone(identifier: "UTC")!

    private func table(hst: Bool, pts: Int, mul: Int, score: Int) -> ScoreTableModel {
        var m = ScoreTableModel()
        m.reset(hst: hst)
        var s = Stats()
        s.verified = ScoreRow(pts: pts, mul: mul, score: score)
        s.raw = s.verified
        m.update(s, hst: hst)
        return m
    }

    @Test(arguments: [true, false])
    func hstAlwaysPops(_ byUser: Bool) {
        let o = ContestEndPolicy.outcome(mode: .hst, stoppedByUser: byUser,
                                         table: table(hst: true, pts: 0, mul: 0, score: 77),
                                         call: " KF5O ", hamName: "Mike", hiScore: 0,
                                         now: now, timeZone: utc)
        #expect(o == .hst(line: "2026-03-04 05:06\tKF5O\tMike\t77", message: "HST Score: 77"))
    }

    @Test func wpxWhenTimeRunsOut() {
        let o = ContestEndPolicy.outcome(mode: .wpx, stoppedByUser: false,
                                         table: table(hst: false, pts: 12, mul: 10, score: 120),
                                         call: "KF5O ", hamName: "", hiScore: 100,
                                         now: now, timeZone: utc)
        let inner = "2026-03-04 KF5O 12 10 "
        #expect(o == .wpx(line: stampScoreLine(inner), score: 120, newRecord: true, hiScore: 120))
    }

    @Test(arguments: [(100, 100, false, 100), (100, 101, true, 101), (150, 100, false, 150), (0, 0, false, 0)])
    func wpxRecord(_ hi: Int, _ score: Int, _ record: Bool, _ newHi: Int) {
        let o = ContestEndPolicy.outcome(mode: .wpx, stoppedByUser: false,
                                         table: table(hst: false, pts: score, mul: 1, score: score),
                                         call: "K1", hamName: "", hiScore: hi, now: now, timeZone: utc)
        guard case .wpx(_, let s, let newRecord, let h) = o else {
            Issue.record("expected WPX")
            return
        }
        #expect(s == score)
        #expect(newRecord == record)
        #expect(h == newHi)
    }

    @Test(arguments: [
        (RunMode.wpx, true), (RunMode.pileUp, false), (RunMode.pileUp, true),
        (RunMode.single, false), (RunMode.stop, false),
    ])
    func nothingElse(_ m: RunMode, _ byUser: Bool) {
        #expect(ContestEndPolicy.outcome(mode: m, stoppedByUser: byUser, table: ScoreTableModel(),
                                         call: "K1", hamName: "", hiScore: 0, now: now,
                                         timeZone: utc) == .none)
    }

    @Test func dateIsLocalWallClockAndLocaleFree() throws {
        // 05:06 UTC is the previous day in Los Angeles.
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(ContestEndPolicy.date(now, la) == "2026-03-03")
        #expect(ContestEndPolicy.time(now, la) == "21:06")
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(ContestEndPolicy.date(now, tokyo) == "2026-03-04")
        #expect(ContestEndPolicy.time(now, tokyo) == "14:06")
    }

    @Test func wpxLineIsStamped() {
        let line = ContestEndPolicy.wpxLine(now: now, timeZone: utc, call: "VE3NEA", pts: "1", mul: "1")
        #expect(line.hasPrefix("2026-03-04 VE3NEA 1 1 ["))
        #expect(line.hasSuffix("]"))
        #expect(line.count == "2026-03-04 VE3NEA 1 1 ".count + 10)
    }
}

struct ScoreFilesTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "mr-appcore-\(UUID().uuidString)")
    }

    @Test func paths() {
        let f = ScoreFiles(baseDir: URL(filePath: "/x/MorseRunner"))
        #expect(f.scoreList.lastPathComponent == "scores.lst")
        #expect(f.hstResults.lastPathComponent == "HstResults.txt")
        #expect(f.recording.lastPathComponent == "MorseRunner.wav")
    }

    @Test func appendCreatesAndAppends() throws {
        let dir = tempDir().appending(path: "nested")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let f = ScoreFiles(baseDir: dir)
        #expect(f.scoreListContents() == nil)
        try f.append("one", to: f.scoreList)
        try f.append("two", to: f.scoreList)
        #expect(f.scoreListContents() == "one\ntwo\n")
        #expect(!f.recordingExists)
    }

    @Test func appendRepairsAMissingLineBreak() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = ScoreFiles(baseDir: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: f.hstResults)
        try f.append("new", to: f.hstResults)
        #expect(try String(contentsOf: f.hstResults, encoding: .utf8) == "old\nnew\n")
    }

    @Test func appendSurfacesErrors() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A file where the directory should be.
        let blocker = dir.appending(path: "blocked")
        try Data().write(to: blocker)
        let f = ScoreFiles(baseDir: blocker)
        #expect(throws: (any Error).self) { try f.append("x", to: f.scoreList) }
    }
}

struct MenuSpecTests {
    @Test func sendItemsMatchTheFKeys() {
        #expect(MenuSpec.sendItems.map(\.functionKey) == Array(1...8))
        #expect(MenuSpec.sendItems.map(\.message) == [.cq, .nr, .tu, .myCall, .hisCall, .b4, .qm, .nilMsg])
        #expect(MenuSpec.sendItems.map(\.title)
                == ["CQ", "Number", "TU", "My Call", "His Call", "QSO B4", "<?>", "NIL"])
        for item in MenuSpec.sendItems {
            #expect(item.buttonCaption.hasPrefix("F\(item.functionKey)  "))
            #expect(item.shortcut == MenuShortcut(key: FunctionKey.f(item.functionKey)))
        }
    }

    @Test func runItems() {
        #expect(MenuSpec.runItems.map(\.mode) == [.pileUp, .single, .wpx, .hst])
        #expect(MenuSpec.runItems[3].shortcut == MenuShortcut(key: FunctionKey.f8, control: true))
    }

    @Test func shortcutsAreUniqueExceptTheDocumentedF8() {
        var seen: [MenuShortcut: Int] = [:]
        for s in MenuSpec.sendItems.map(\.shortcut) + MenuSpec.runItems.compactMap(\.shortcut) {
            seen[s, default: 0] += 1
        }
        let dupes = seen.filter { $0.value > 1 }.map(\.key)
        #expect(dupes == [MenuShortcut(key: FunctionKey.f8)])
        #expect(MenuSpec.items(with: MenuShortcut(key: FunctionKey.f8)) == ["Run/Pile-Up", "Send/NIL"])
    }

    @Test func f8OwnerFollowsTheRunState() {
        let f8 = MenuShortcut(key: FunctionKey.f8)
        #expect(MenuSpec.shortcutOwner(f8, running: false) == "Run/Pile-Up")
        #expect(MenuSpec.shortcutOwner(f8, running: true) == "Send/NIL")
        let ctrlF8 = MenuShortcut(key: FunctionKey.f8, control: true)
        #expect(MenuSpec.shortcutOwner(ctrlF8, running: false) == "Run/HST Competition")
        #expect(MenuSpec.shortcutOwner(ctrlF8, running: true) == nil)
        #expect(MenuSpec.runShortcutActive(MenuSpec.runItems[0], running: false))
        #expect(!MenuSpec.runShortcutActive(MenuSpec.runItems[0], running: true))
        #expect(!MenuSpec.runShortcutActive(MenuSpec.runItems[1], running: false))
        #expect(MenuSpec.shortcutOwner(MenuShortcut(key: FunctionKey.f(1)), running: false) == "Send/CQ")
    }

    @Test func valueLists() {
        #expect(MenuSpec.speeds == [10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60])
        #expect(MenuSpec.monitorLevels.map(\.title) == ["-60 dB", "-40 dB", "-20 dB", "0 dB", "+20 dB"])
        #expect(MenuSpec.activities == Array(1...9))
        #expect(MenuSpec.durations == [5, 10, 15, 30, 60, 90, 120])
        #expect(MenuSpec.durations.allSatisfy { SpinRange.duration.typedValue(String($0)) == $0 })
        #expect(MenuSpec.conditions == ["QRN", "QRM", "QSB", "Flutter", "LIDS"])
        #expect(URL(string: MenuSpec.hiScoreURL)?.scheme == "https")
        #expect(URL(string: MenuSpec.webPageURL)?.scheme == "https")
    }

    @Test(arguments: [
        (UInt32(16_711_401), 0xE9, 0xFE, 0xFE), (UInt32(12_902_431), 0x1F, 0xE0, 0xC4),
        (UInt32(14_151_712), 0x20, 0xF0, 0xD7), (UInt32(0x0000FF), 0xFF, 0, 0), (UInt32(0xFF0000), 0, 0, 0xFF),
    ])
    func delphiColors(_ bgr: UInt32, _ r: Int, _ g: Int, _ b: Int) {
        let c = DelphiColor.rgb(bgr)
        #expect(c.red == r && c.green == g && c.blue == b)
    }
}
