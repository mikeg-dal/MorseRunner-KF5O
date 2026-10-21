// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Contest paths beyond the C++-ported ContestTests: WAV recording,
// stop/settings edge cases, buffer sizes, every player message, the
// callbacks and the API-boundary preconditions.

import Foundation
import MRCore
@testable import MRSimulation
import Testing

private let kBuf = AudioK.defaultBufferSamples

private func makeContest(seed: UInt64, bufferSize: Int = kBuf,
                         _ configure: (inout ContestSettings) -> Void = { _ in }) -> Contest {
    let c = Contest(calls: HardcodedCallsignSource(), bufferSize: bufferSize, random: Random(seed: seed))
    var s = c.settings
    configure(&s)
    c.setSettings(s)
    return c
}

private func render(_ c: Contest, blocks: Int) {
    var buf = [Float](repeating: 0, count: c.bufferSize)
    for _ in 0..<blocks {
        c.renderNextBlock(&buf)
    }
}

/// Renders until the player stops sending; returns how many blocks that took.
@discardableResult
private func renderUntilPlayerIdle(_ c: Contest, limit: Int = 2000) -> Int {
    var buf = [Float](repeating: 0, count: c.bufferSize)
    var n = 0
    while c.playerSending && n < limit {
        c.renderNextBlock(&buf)
        n += 1
    }
    return n
}

private func readLE32(_ d: Data, _ offset: Int) -> UInt32 {
    d[offset..<(offset + 4)].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
}

@Suite struct ContestRecordingTests {
    @Test func recordsEveryAudibleBlockToWav() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mr-rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("rec.wav").path

        let c = makeContest(seed: 31)
        c.setRunMode(.pileUp)
        #expect(c.enableAudioRecording(path: path))
        render(c, blocks: 20)
        c.disableAudioRecording()
        render(c, blocks: 3)  // no longer recorded

        // Blocks 1…5 are the silent startup skip, returned before the WAV
        // tap; blocks 6…20 are written.
        let samples = (20 - (AudioK.startupSkipBlocks - 1)) * kBuf
        let wav = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(wav.count == 44 + samples * 2)
        #expect(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        #expect(readLE32(wav, 4) == UInt32(36 + samples * 2))
        #expect(readLE32(wav, 24) == UInt32(AudioK.sampleRate))
        #expect(readLE32(wav, 40) == UInt32(samples * 2))
    }

    @Test func badPathReportsFailureAndKeepsRunning() {
        let c = makeContest(seed: 32)
        c.setRunMode(.pileUp)
        #expect(!c.enableAudioRecording(path: "/nonexistent-dir-\(UUID().uuidString)/x.wav"))
        render(c, blocks: 10)
        c.disableAudioRecording()  // harmless with nothing open
        #expect(c.currentBlockIndex == 10)
    }

    @Test func recordingDoesNotChangeTheAudio() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("mr-rec-\(UUID().uuidString).wav").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let a = makeContest(seed: 33)
        let b = makeContest(seed: 33)
        a.setRunMode(.pileUp)
        b.setRunMode(.pileUp)
        #expect(b.enableAudioRecording(path: path))
        var x = [Float](repeating: 0, count: kBuf)
        var y = [Float](repeating: 0, count: kBuf)
        for _ in 0..<30 {
            a.renderNextBlock(&x)
            b.renderNextBlock(&y)
            #expect(x == y)
        }
        b.disableAudioRecording()
    }
}

@Suite struct ContestControlTests {
    @Test func requestStopWhileStoppedDoesNothing() {
        let c = makeContest(seed: 41)
        c.setRunMode(.stop)  // a new Contest starts in the default mode, .pileUp
        var ended = 0
        c.onEndOfSession = { _, _ in ended += 1 }
        c.requestStop()
        render(c, blocks: 20)
        #expect(ended == 0)
        #expect(c.currentBlockIndex == 0)
        // Starting a run clears the pending request.
        c.setRunMode(.pileUp)
        render(c, blocks: 20)
        #expect(ended == 0)
        #expect(c.runMode == .pileUp)
    }

    @Test func requestStopDuringStartupSkipFiresAtFirstAudibleBlock() {
        let c = makeContest(seed: 42)
        c.setRunMode(.single)
        var endedAt: Int?
        var byUser: Bool?
        c.onEndOfSession = { [unowned c] _, u in
            endedAt = c.currentBlockIndex
            byUser = u
        }
        render(c, blocks: 2)
        c.requestStop()
        var n = 2
        while endedAt == nil && n < 20 {
            render(c, blocks: 1)
            n += 1
        }
        #expect(endedAt == AudioK.startupSkipBlocks)
        #expect(byUser == true)
        #expect(c.runMode == .stop)
        #expect(c.stations.isEmpty)
    }

    @Test func pitchAndBandwidthChangeMidRun() {
        let c = makeContest(seed: 43)
        c.setRunMode(.pileUp)
        c.playerSendMessage(.cq)
        render(c, blocks: 30)
        var s = c.settings
        s.pitchHz = 750
        s.rxBandwidthHz = 250
        c.setSettings(s)
        #expect(c.player.pitchHz == 750)
        #expect(c.settings.rxBandwidthHz == 250)
        #expect(c.runMode == .pileUp)  // read-modify-write keeps the mode
        var buf = [Float](repeating: 0, count: kBuf)
        for _ in 0..<50 {
            #expect(c.renderNextBlock(&buf) == kBuf)
            #expect(buf.allSatisfy { $0.isFinite })
        }
    }

    // Like the C++, setSettings replaces the whole struct, mode included,
    // without setRunMode's reset.
    @Test func setSettingsOverwritesModeWithoutReset() {
        let c = makeContest(seed: 44)
        c.setRunMode(.single)
        render(c, blocks: 40)
        let block = c.currentBlockIndex
        let stationCount = c.stations.count
        c.setSettings(ContestSettings())  // default mode .pileUp
        #expect(c.runMode == .pileUp)
        #expect(c.currentBlockIndex == block)
        #expect(c.stations.count == stationCount)
    }

    @Test func settingsAndPlayerFollowSetSettings() {
        let c = makeContest(seed: 45) {
            $0.myCallsign = "KF5O"
            $0.wpm = 25
            $0.pitchHz = 500
        }
        #expect(c.settings.myCallsign == "KF5O")
        #expect(c.myCallsign == "KF5O")
        #expect(c.player.myCall == "KF5O")
        #expect(c.player.wpm == 25)
        #expect(c.targetWpm == 25)
        #expect(c.player.pitchHz == 500)
        #expect(c.bufferSize == kBuf)
    }

    @Test func blockClockAdvancesOnlyWhileRunning() {
        let c = makeContest(seed: 46)
        c.setRunMode(.stop)
        render(c, blocks: 5)
        #expect(c.currentBlockIndex == 0)
        c.setRunMode(.pileUp)
        render(c, blocks: 100)
        #expect(c.currentBlockIndex == 100)
        #expect(c.currentMinute == Float(AudioK.blocksToSeconds(100, bufSize: kBuf) / 60.0))
        c.setRunMode(.stop)
        render(c, blocks: 10)
        #expect(c.currentBlockIndex == 100)  // Pascal keeps the final time
        c.setRunMode(.wpx)
        #expect(c.currentBlockIndex == 0)
        #expect(c.currentMinute == 0)
    }

    @Test(arguments: [128, 2048])
    func nonDefaultBufferSizesRun(bufferSize: Int) {
        let c = makeContest(seed: 47, bufferSize: bufferSize) { $0.activity = 6 }
        c.setRunMode(.pileUp)
        c.playerSendMessage(.cq)
        var buf = [Float](repeating: 0, count: bufferSize)
        let blocks = 2 * 11025 * 20 / bufferSize  // ~40 s of audio
        for _ in 0..<blocks {
            #expect(c.renderNextBlock(&buf) == bufferSize)
            #expect(buf.allSatisfy { $0.isFinite && abs($0) <= 1.5 })
        }
        #expect(c.currentBlockIndex == blocks)
        #expect(c.currentMinute == Float(AudioK.blocksToSeconds(Double(blocks), bufSize: bufferSize) / 60.0))
    }

    @Test func largerOutputBufferIsFilledOnlyUpToBufferSize() {
        let c = makeContest(seed: 48)
        c.setRunMode(.pileUp)
        render(c, blocks: 10)
        var buf = [Float](repeating: 99, count: kBuf + 100)
        #expect(c.renderNextBlock(&buf) == kBuf)
        #expect(buf[kBuf...].allSatisfy { $0 == 99 })
        #expect(buf[0..<kBuf].contains { $0 != 99 })
    }

    @Test func abortWithNothingInFlight() {
        let c = makeContest(seed: 49)
        c.setRunMode(.pileUp)
        let info = c.playerAbortSend()
        #expect(!info.hadHisCall)
        #expect(!info.hadNr)
        #expect(c.player.state == .listening)
        #expect(c.player.msg == MessageSet([.garbage]))
        #expect(c.stations.isEmpty)  // a "finished" garbage send spawns nobody
    }

    @Test func abortReportsWhatWasBeingSent() {
        let c = makeContest(seed: 50)
        c.setRunMode(.pileUp)
        c.playerSendMessage(.hisCall, callField: "W1AW")
        c.playerSendMessage(.nr)
        let info = c.playerAbortSend()
        #expect(info.hadHisCall)
        #expect(info.hadNr)
        #expect(!c.playerSending)
    }
}

@Suite struct ContestPlayerMessageTests {
    // F-keys and ESM only send 1…8, but every Message must be sendable.
    @Test(arguments: Array(9...22))
    func everyOtherMessageSends(raw: Int) throws {
        let m = try #require(Message(rawValue: raw))
        let c = makeContest(seed: 60)
        c.setRunMode(.pileUp)
        c.playerSendMessage(m, callField: "W1AW")
        #expect(c.player.msg.contains(m))
        // Garbage has no text, so nothing keys; everything else does.
        #expect(c.playerSending == (m != .garbage))
        let blocks = renderUntilPlayerIdle(c)
        #expect(blocks < 2000)
        #expect(c.player.state == .listening)
        #expect(c.player.msg.contains(m))
        #expect(c.player.pieceCount == 0)
        // Only a CQ (or TU + MyCall after a QSO) draws callers.
        #expect(c.stations.dxCount == 0)
    }

    @Test func qsyKeysThePlayersHisCall() {
        let c = makeContest(seed: 61)
        c.setRunMode(.pileUp)
        c.playerSendMessage(.hisCall, callField: "W1AW")
        renderUntilPlayerIdle(c)
        c.playerSendMessage(.qsy)
        // "<his>  QSY QSY": MyStation splits it, so the call is keyed.
        #expect(c.player.pieceCount == 2)
        #expect(c.player.accumulatedText == "W1AW")
        renderUntilPlayerIdle(c)
        #expect(c.player.pieceCount == 0)
    }

    @Test func pieceFinishedCallbackFiresPerPiece() {
        let c = makeContest(seed: 62)
        c.setRunMode(.pileUp)
        var pieces = 0
        c.onPlayerPieceFinished = { pieces += 1 }
        #expect(c.onPlayerPieceFinished != nil)
        c.playerSendMessage(.hisCall, callField: "W1AW")
        c.playerSendMessage(.nr)
        renderUntilPlayerIdle(c)
        #expect(pieces == 2)
        c.onPlayerPieceFinished = nil
        c.playerSendMessage(.tu)
        renderUntilPlayerIdle(c)
        #expect(pieces == 2)
    }

    // CallsFromKeyer: an external keyer sends the call, so a blank is
    // keyed in its place — except in WPX and HST, where Pascal keeps it.
    @Test func callsFromKeyerBlanksTheCallOutsideWpxAndHst() {
        func hisCallBlocks(_ mode: RunMode, fromKeyer: Bool) -> (Int, String) {
            let c = makeContest(seed: 63) {
                $0.callsFromKeyer = fromKeyer
                $0.qrm = false
                $0.qrn = false
            }
            c.setRunMode(mode)
            c.playerSendMessage(.hisCall, callField: "W1AWW")
            let text = c.player.accumulatedText
            #expect(c.heardCallsign == "W1AWW")
            return (renderUntilPlayerIdle(c), text)
        }
        let keyed = hisCallBlocks(.pileUp, fromKeyer: false)
        let blank = hisCallBlocks(.pileUp, fromKeyer: true)
        #expect(keyed.1 == "W1AWW")
        #expect(blank.1 == " ")
        #expect(blank.0 < keyed.0)
        for mode in [RunMode.wpx, .hst] {
            let kept = hisCallBlocks(mode, fromKeyer: true)
            #expect(kept.1 == "W1AWW")
            #expect(kept.0 == hisCallBlocks(mode, fromKeyer: false).0)
        }
    }
}

@Suite struct ContestPreconditionTests {
    @Test func zeroBufferSizeTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Contest(calls: HardcodedCallsignSource(), bufferSize: 0, random: Random(seed: 1))
        }
    }

    @Test func zeroWpmTraps() async {
        await #expect(processExitsWith: .failure) {
            let c = Contest(calls: HardcodedCallsignSource(), bufferSize: 512, random: Random(seed: 1))
            var s = c.settings
            s.wpm = 0
            c.setSettings(s)
        }
    }

    #if DEBUG
    @Test func pieceFinishedCallbackMustNotReenter() async {
        await #expect(processExitsWith: .failure) {
            let c = Contest(calls: HardcodedCallsignSource(), bufferSize: 512, random: Random(seed: 1))
            c.setRunMode(.pileUp)
            c.onPlayerPieceFinished = { [unowned c] in c.playerSendMessage(.tu) }
            c.playerSendMessage(.cq)
            var buf = [Float](repeating: 0, count: 512)
            for _ in 0..<500 { c.renderNextBlock(&buf) }
        }
    }

    @Test func qsoCompletedCallbackMustNotReenter() async {
        await #expect(processExitsWith: .failure) {
            let c = Contest(calls: HardcodedCallsignSource(), bufferSize: 512, random: Random(seed: 1))
            c.setRunMode(.pileUp)
            let dx = c.stations.addCaller(c, "W1AW")
            dx.dxOperator.setState(.done)
            c.onQsoCompleted = { [unowned c] _ in c.playerSendMessage(.tu) }
            c.qsoLogged("W1AW")
        }
    }
    #endif

    @Test func callbacksMayStillHandOff() {
        let c = makeContest(seed: 70)
        c.setRunMode(.pileUp)
        let dx = c.stations.addCaller(c, "W1AW")
        dx.dxOperator.setState(.done)
        var got: [Contest.CompletedQso] = []
        c.onQsoCompleted = { got.append($0) }
        c.qsoLogged("w1aw")
        #expect(got.count == 1)
        #expect(got.first?.call == "W1AW")
        #expect(got.first?.rst == dx.rst)
        #expect(got.first?.nr == dx.nr)
        #expect(dx.shouldRemove)
        // The engine can be used again once the callback has returned.
        c.playerSendMessage(.tu)
        #expect(c.playerSending)
    }
}
