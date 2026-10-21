// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Whole-contest acceptance test against tools/golden/golden_sim.cpp.
// Each scenario replays the C++ robot operator's recorded actions and
// must reproduce the per-block trace (player + every station's state,
// plus audio statistics) line for line.

import Foundation
import MRCore
@testable import MRSimulation
import MRTestSupport
import Testing

private struct ScenarioSettings: Decodable {
    let myCallsign: String
    let wpm: Int
    let pitchHz: Int
    let rxBandwidthHz: Int
    let ritHz: Int
    let qsk: Bool
    let qrn: Bool
    let qrm: Bool
    let qsb: Bool
    let flutter: Bool
    let lids: Bool
    let activity: Int
    let durationMinutes: Int
    let selfMonGain01: Float
    let callsFromKeyer: Bool
}

private struct Action: Decodable {
    let b: Int
    let a: String
    let m: Int?
    let call: String?
    let ok: Bool?
    let his: Bool?
    let nr: Bool?
}

private struct Scenario: Decodable {
    let seed: UInt64
    let mode: Int
    let maxBlocks: Int
    let settings: ScenarioSettings
    let actions: [Action]
}

/// Repo-relative Master.dta, located from this file.
func masterDtaURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MRSimulationTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // Swift
        .deletingLastPathComponent()  // repo
        .appendingPathComponent("resources/data/Master.dta")
}

private func kindOf(_ s: Station) -> String {
    if s is DxStation { return "D" }
    if s is QrmStation { return "Q" }
    if s is QrnStation { return "N" }
    return "?"
}

private func num(_ x: Float) -> String { String(format: "%.9g", Double(x)) }
private func num(_ x: Double) -> String { String(format: "%.17g", x) }

/// Same format as golden_sim.cpp traceLine().
private func traceLine(_ b: Int, _ c: Contest, _ out: [Float]) -> String {
    var sum = 0.0
    var sq = 0.0
    for x in out {
        sum += Double(x)
        sq += Double(x) * Double(x)
    }
    let me = c.player
    var line = "\(b) me=\(me.state.rawValue),\(me.msg.rawValue),\(me.nr),\(me.hisCall),\(me.pieceCount)|"
    for s in c.stations {
        let t = s.timeout == kNeverTimeout ? "N" : String(s.timeout)
        line += "\(kindOf(s)):\(s.myCall),\(s.state.rawValue),\(t),\(s.msg.rawValue),w\(s.wpm),"
            + "p\(s.pitchHz),a\(num(s.amplitude)),n\(s.nr),r\(s.rst)"
        if let dx = s as? DxStation {
            let op = dx.dxOperator
            line += ",o\(op.state.rawValue),pt\(op.patience),rc\(op.repeatCount),sk\(op.skills)"
        }
        line += ";"
    }
    line += "|" + num(sum) + "," + num(sq)
    return line
}

private func runScenario(_ name: String) throws {
    let sc = try Fixtures.json(Scenario.self, "sim/\(name).json")
    let expectedText = try String(contentsOf: Fixtures.url("sim/\(name).trace"), encoding: .utf8)
    var expected = expectedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if expected.last == "" { expected.removeLast() }

    let rng = Random(seed: sc.seed)
    let db = CallsignDb()
    #expect(db.load(from: masterDtaURL()))
    let c = Contest(calls: db, bufferSize: AudioK.defaultBufferSamples, random: rng)

    var s = ContestSettings()
    s.myCallsign = sc.settings.myCallsign
    s.wpm = sc.settings.wpm
    s.pitchHz = sc.settings.pitchHz
    s.rxBandwidthHz = sc.settings.rxBandwidthHz
    s.ritHz = sc.settings.ritHz
    s.qsk = sc.settings.qsk
    s.qrn = sc.settings.qrn
    s.qrm = sc.settings.qrm
    s.qsb = sc.settings.qsb
    s.flutter = sc.settings.flutter
    s.lids = sc.settings.lids
    s.activity = sc.settings.activity
    s.durationMinutes = sc.settings.durationMinutes
    s.selfMonGain01 = sc.settings.selfMonGain01
    s.callsFromKeyer = sc.settings.callsFromKeyer
    c.setSettings(s)
    c.setRunMode(RunMode(rawValue: sc.mode)!)

    // Lines are collected as the C++ appends them (events between block
    // lines).
    final class Sink { var lines: [String] = []; var ended = false }
    let sink = Sink()
    c.onQsoCompleted = { q in sink.lines.append("EV qso \(q.call) \(q.rst) \(q.nr)") }
    c.onEndOfSession = { m, byUser in
        sink.lines.append("EV end \(m.rawValue) \(byUser ? "1" : "0")")
        sink.ended = true
    }
    c.onPlayerPieceFinished = { sink.lines.append("EV piece") }

    var actionIdx = 0
    var out = [Float](repeating: 0, count: AudioK.defaultBufferSamples)
    var b = 0
    while b < sc.maxBlocks && !sink.ended {
        while actionIdx < sc.actions.count && sc.actions[actionIdx].b == b {
            let a = sc.actions[actionIdx]
            actionIdx += 1
            switch a.a {
            case "send":
                c.playerSendMessage(Message(rawValue: a.m!)!, callField: a.call ?? "")
            case "edit":
                let ok = c.playerEditedCall(a.call!)
                #expect(ok == a.ok!, "\(name): edit at block \(b)")
            case "log":
                c.qsoLogged(a.call!)
            case "abort":
                let info = c.playerAbortSend()
                #expect(info.hadHisCall == a.his! && info.hadNr == a.nr!,
                        "\(name): abort flags at block \(b)")
            case "stop":
                c.requestStop()
            default:
                Issue.record("\(name): unknown action \(a.a)")
            }
        }
        c.renderNextBlock(&out)
        sink.lines.append(traceLine(b, c, out))
        b += 1
    }
    #expect(actionIdx == sc.actions.count, "\(name): unreplayed actions")

    let got = sink.lines
    for i in 0..<min(got.count, expected.count) where got[i] != expected[i] {
        Issue.record("""
            \(name): first mismatch at trace line \(i + 1)
              expected: \(expected[i])
              got:      \(got[i])
            """)
        return
    }
    #expect(got.count == expected.count, "\(name): line count \(got.count) vs \(expected.count)")
}

@Suite struct GoldenSimTests {
    @Test(arguments: ["pileup_default", "pileup_odd", "single", "wpx", "hst", "stopped_120wpm"])
    func scenario(_ name: String) throws {
        try runScenario(name)
    }
}
