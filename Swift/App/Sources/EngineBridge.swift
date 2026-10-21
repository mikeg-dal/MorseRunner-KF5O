// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The main thread's handle on the simulation. Pascal's MainForm called
// straight into Tst; here every call is queued to the "mr-sim" thread and
// runs between audio blocks, and every event Tst raised comes back on the
// main thread. No DSP happens on the main thread.

import Foundation
import MRAudio
import MRCore
import MRSimulation
import os

/// Tst → MainForm, delivered on the main thread.
@MainActor
protocol EngineEvents: AnyObject {
    func engineClock(seconds: Double)
    func enginePileUpCount(_ n: Int)
    func engineContestEnded(mode: RunMode, stoppedByUser: Bool)
    func engineQsoTruth(call: String, rst: Int, nr: Int)
    func enginePieceFinished()
    func engineCallEditResult(applied: Bool)
    func engineSendAborted(hadHisCall: Bool, hadNr: Bool)
}

/// MainForm → Tst. EngineBridge is the real one; tests use a fake.
@MainActor
protocol EngineCommanding: AnyObject {
    var events: (any EngineEvents)? { get set }

    func start()
    /// Stops the audio and the sim thread. Idempotent.
    func shutdown()

    /// All settings at once (FromIni). The run mode is left as it is.
    func configure(_ settings: ContestSettings)
    func setRunMode(_ m: RunMode)
    func requestStop()
    func send(_ m: Message, callField: String)
    /// Log.SaveQso's side of Tst: `stamped` gets the contest time of the
    /// block being rendered (Pascal Qso.T := BlocksToSeconds(BlockNumber))
    /// before the DX lookup can report the truth.
    func logQso(_ call: String, stamped: @escaping @MainActor @Sendable (Double) -> Void)
    func editCall(_ text: String)
    func abortSend()
    func setRecording(_ url: URL?)

    func setMyCall(_ v: String)
    func setWpm(_ v: Int)
    func setPitch(_ v: Int)
    func setBandwidth(_ v: Int)
    func setRit(_ v: Int)
    func setQsk(_ v: Bool)
    func setActivity(_ v: Int)
    func setDuration(_ v: Int)
    func setMonitorLevel(_ v: Float)
    func setCallsFromKeyer(_ v: Bool)
    func setConditions(qrn: Bool, qrm: Bool, qsb: Bool, flutter: Bool, lids: Bool)
}

/// Where the sim thread's callbacks land. Main-actor isolated, hence
/// Sendable: the callbacks capture it and hop to the main thread.
@MainActor
private final class EventSink {
    weak var events: (any EngineEvents)?
}

@MainActor
final class EngineBridge: EngineCommanding {
    private nonisolated static let log = Logger(subsystem: "com.garciamike1.morserunner", category: "engine")

    var events: (any EngineEvents)? {
        get { sink.events }
        set { sink.events = newValue }
    }

    private let sink: EventSink
    private let sim: SimulationThread<Contest>
    private let output: AudioOutput
    private var uiTimer: Timer?
    private var isShutDown = false

    init() {
        let sink = EventSink()
        self.sink = sink
        let ring = AudioBlockRing()
        sim = SimulationThread(ring: ring, renderer: Self.makeContest(sink: sink))
        output = AudioOutput(ring: ring)
    }

    /// Built outside the main actor: the contest belongs to the sim
    /// thread from birth, and its callbacks only hop to the main thread.
    private nonisolated static func makeContest(sink: EventSink) -> sending Contest {
        let contest = Contest(calls: loadCalls(),
                              bufferSize: AudioK.defaultBufferSamples, random: Random())
        contest.setRunMode(.stop)
        contest.onEndOfSession = { mode, byUser in
            postToMain {
                sink.events?.engineContestEnded(mode: mode, stoppedByUser: byUser)
            }
        }
        contest.onQsoCompleted = { q in
            let call = q.call, rst = q.rst, nr = q.nr
            postToMain {
                sink.events?.engineQsoTruth(call: call, rst: rst, nr: nr)
            }
        }
        contest.onPlayerPieceFinished = {
            postToMain { sink.events?.enginePieceFinished() }
        }
        return contest
    }

    private nonisolated static func loadCalls() -> any CallsignSource {
        let db = CallsignDb()
        if let url = Bundle.main.url(forResource: "Master", withExtension: "dta"), db.load(from: url) {
            return db
        }
        log.error("Master.dta missing or unreadable; using the built-in call generator")
        return HardcodedCallsignSource()
    }

    func start() {
        sim.start()
        do {
            try output.start()
        } catch {
            Self.log.error("audio output failed to start: \(String(describing: error), privacy: .public)")
        }
        // GetAudio updates Panel2 / Panel7 / Panel4 every block; 30 Hz is
        // plenty for the eye. Common modes: keeps ticking while a menu is
        // open or a modal dialog runs.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        uiTimer?.invalidate()
        uiTimer = nil
        output.stop()
        sim.stop()
    }

    private func pollClock() {
        let sink = sink
        sim.perform { c in
            let seconds = AudioK.blocksToSeconds(Double(c.currentBlockIndex), bufSize: c.bufferSize)
            let dx = c.stations.dxCount
            postToMain {
                sink.events?.engineClock(seconds: seconds)
                sink.events?.enginePileUpCount(dx)
            }
        }
    }

    private func mutate(_ change: @escaping @Sendable (inout ContestSettings) -> Void) {
        sim.perform { c in
            var s = c.settings
            change(&s)
            c.setSettings(s)
        }
    }

    // MARK: Commands (MainForm → Tst)

    func configure(_ settings: ContestSettings) {
        mutate { s in
            let mode = s.mode
            s = settings
            s.mode = mode
        }
    }

    func setRunMode(_ m: RunMode) { sim.perform { $0.setRunMode(m) } }
    func requestStop() { sim.perform { $0.requestStop() } }
    func send(_ m: Message, callField: String) { sim.perform { $0.playerSendMessage(m, callField: callField) } }

    func logQso(_ call: String, stamped: @escaping @MainActor @Sendable (Double) -> Void) {
        sim.perform { c in
            let seconds = AudioK.blocksToSeconds(Double(c.currentBlockIndex), bufSize: c.bufferSize)
            postToMain { stamped(seconds) }
            c.qsoLogged(call)
        }
    }

    func editCall(_ text: String) {
        let sink = sink
        sim.perform { c in
            let ok = c.playerEditedCall(text)
            postToMain { sink.events?.engineCallEditResult(applied: ok) }
        }
    }

    func abortSend() {
        let sink = sink
        sim.perform { c in
            let info = c.playerAbortSend()
            let his = info.hadHisCall, nr = info.hadNr
            postToMain {
                sink.events?.engineSendAborted(hadHisCall: his, hadNr: nr)
            }
        }
    }

    func setRecording(_ url: URL?) {
        let path = url?.path(percentEncoded: false)
        sim.perform { c in
            if let path { c.enableAudioRecording(path: path) } else { c.disableAudioRecording() }
        }
    }

    // MARK: Settings

    func setMyCall(_ v: String) { mutate { $0.myCallsign = v } }
    func setWpm(_ v: Int) { mutate { $0.wpm = v } }
    func setPitch(_ v: Int) { mutate { $0.pitchHz = v } }
    func setBandwidth(_ v: Int) { mutate { $0.rxBandwidthHz = v } }
    func setRit(_ v: Int) { mutate { $0.ritHz = v } }
    func setQsk(_ v: Bool) { mutate { $0.qsk = v } }
    func setActivity(_ v: Int) { mutate { $0.activity = v } }
    func setDuration(_ v: Int) { mutate { $0.durationMinutes = v } }
    func setMonitorLevel(_ v: Float) { mutate { $0.selfMonGain01 = v } }
    func setCallsFromKeyer(_ v: Bool) { mutate { $0.callsFromKeyer = v } }

    func setConditions(qrn: Bool, qrm: Bool, qsb: Bool, flutter: Bool, lids: Bool) {
        mutate {
            $0.qrn = qrn
            $0.qrm = qrm
            $0.qsb = qsb
            $0.flutter = flutter
            $0.lids = lids
        }
    }
}
