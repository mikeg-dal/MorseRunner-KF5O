// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Contest.pas TContest (C++ src/simulation/Contest). The
// simulation orchestrator: owns the player station, the audible-source
// collection, the DSP chain, and drives one audio block of mixed output
// per call to renderNextBlock.
//
// Pascal-equivalent flow for renderNextBlock:
//   1. Fill a complex (I/Q) noise buffer of bufSize samples.
//   2. Inject QRN spikes (per-sample 1% chance) and QRN-station burst
//      spawns (per-block 1%).
//   3. Spawn QRM stations with 0.0002 per-block probability.
//   4. For each live station, pull its keying envelope chunk and mix
//      into the I/Q buffer with the station's BFO + global RIT phase.
//   5. Apply the player's self-monitor (QSK ducking if enabled).
//   6. Run the ping-pong moving-average LPF over the I/Q buffer.
//   7. Demodulate complex → real via the Modulator at the player's
//      configured pitch.
//   8. Apply the AGC.
//   9. Scale to Float-PCM range (±1.0) and write to `out`.
//  10. tick() every station, sweep finished ones, fire the
//      end-of-session callback when the contest duration elapses.
//
// Threading: lives entirely on the simulation thread. The callbacks
// (onEndOfSession, onQsoCompleted, onPlayerPieceFinished) run there too,
// synchronously inside renderNextBlock / qsoLogged; see their docs.

import Darwin
import MRCore
import MRDSP

/// Snapshot of the user-facing knobs Contest cares about per render.
/// Field names mirror the Pascal Ini globals.
public struct ContestSettings: Equatable, Sendable {
    public var myCallsign = "VE3NEA", wpm = 30, pitchHz = 600, rxBandwidthHz = 500,
               ritHz = 0, qsk = true, qrn = true, qrm = true, qsb = true,
               flutter = true, lids = true, activity = 3, durationMinutes = 30
    /// VolumeSlider1.Value
    public var selfMonGain01: Float = 0.75
    /// Ini.CallsFromKeyer (INI-only)
    public var callsFromKeyer = false
    public var mode: RunMode = .pileUp

    public init() {}
}

// PCM output scaling: AGC writes ±~agcMaxOut, the audio output wants
// ±1.0. 1/32768 (the 16-bit PCM full-scale) keeps the original headroom.
private let floatPcmScale: Float = 1.0 / 32768.0
private let agcMaxOut: Float = 20000.0

public final class Contest: Engine {
    public let bufferSize: Int
    private let rng: Random
    private let callsignSource: any CallsignSource
    /// The player's station. Lazy only so it can be handed `self` as its
    /// engine; init forces it at the same point the C++ constructs
    /// `me_` (MyStation's init draws nothing), so it is never nil.
    private lazy var me = MyStation(engine: self)
    public let stations = StationCollection()

    private let filter = PingPongFilter()
    private let modulator: Modulator
    private let agc = Agc()

    private var scratch = ComplexBuf()
    private let realScratch: UnsafeMutableBufferPointer<Float>

    public private(set) var settings = ContestSettings()
    /// Call of the most recent logged QSO this run (Pascal
    /// QsoList[High(QsoList)].Call) and how many QSOs are logged.
    private var lastLoggedCall = ""
    private var qsoCount = 0

    public private(set) var currentBlockIndex = 0
    public private(set) var currentMinute: Float = 0.0
    private var ritPhase: Double = 0.0
    private var qskRfg: Float = 1.0

    private var stopRequested = false
    private var ended = false

    private var wavWriter: WavWriter?

    #if DEBUG
    /// Debug-only reentrancy guard: true while a callback that fires in
    /// the middle of a station walk is running (onQsoCompleted inside the
    /// matchLoggedQso loop, onPlayerPieceFinished inside the player's
    /// getBlock). Public mutating entry points assert it is false.
    private var inStationCallback = false
    #endif

    /// Runs a callback that fires mid-iteration with the reentrancy guard
    /// raised (debug builds only; release just calls it).
    @inline(__always)
    private func withStationCallbackGuard(_ body: () -> Void) {
        #if DEBUG
        let saved = inStationCallback
        inStationCallback = true
        defer { inStationCallback = saved }
        #endif
        body()
    }

    /// Debug-only: traps when a callback re-enters a mutating entry point.
    @inline(__always)
    private func assertNotReentered(_ function: StaticString = #function) {
        #if DEBUG
        assert(!inStationCallback,
               "Contest.\(function) called from inside an onQsoCompleted / onPlayerPieceFinished callback")
        #endif
    }

    public struct CompletedQso: Sendable {
        public let call: String
        public let rst: Int
        public let nr: Int
        /// Contest time.
        public let minute: Float
    }

    public struct AbortInfo: Sendable {
        public let hadHisCall: Bool
        public let hadNr: Bool
    }

    /// Fired when the configured duration elapses or a requested stop
    /// takes effect at the end of a block (Pascal FStopPressed).
    ///
    /// Runs on the simulation thread, synchronously at the very end of
    /// renderNextBlock, after the contest has already switched to
    /// `.stop`. Every station walk has finished by then, so calling back
    /// into the Contest is safe, but the usual pattern is to hop to the
    /// main thread and come back through the command queue.
    public var onEndOfSession: ((RunMode, _ stoppedByUser: Bool) -> Void)?
    /// Fired when a finished DX station matches the last logged QSO
    /// (Pascal DataToLastQso). Carries the DX's own record.
    ///
    /// Runs on the simulation thread, synchronously from qsoLogged or
    /// renderNextBlock, **while the Contest is iterating its stations**.
    /// It must not call back into the Contest (debug builds assert);
    /// post the record elsewhere and return.
    public var onQsoCompleted: ((CompletedQso) -> Void)?
    /// Pascal MainForm.Advance trigger: a piece of the player's message
    /// finished keying.
    ///
    /// Runs on the simulation thread, synchronously inside
    /// renderNextBlock while the player's audio block is being pulled.
    /// It must not call back into the Contest (debug builds assert);
    /// post to another thread and return.
    public var onPlayerPieceFinished: (() -> Void)? {
        get { me.pieceFinished }
        set { me.pieceFinished = newValue }
    }

    /// `bufferSize` is the block length in samples; it must be positive
    /// (the C++ never checks, and every samples→blocks conversion divides
    /// by it).
    public init(calls: any CallsignSource, bufferSize: Int, random: Random) {
        precondition(bufferSize > 0, "Contest bufferSize must be > 0, got \(bufferSize)")
        self.bufferSize = bufferSize
        rng = random
        callsignSource = calls
        modulator = Modulator(sampleRate: AudioK.sampleRate, carrierFreq: 600.0)
        realScratch = UnsafeMutableBufferPointer<Float>.allocate(capacity: bufferSize)
        realScratch.initialize(repeating: 0.0)
        _ = me  // C++: me_ = std::make_unique<MyStation>(this)

        // One-time AGC setup. The parameters are constants; mutating them
        // later would reset the AGC delay line and cause an audible click.
        agc.setMaxOut(agcMaxOut)
        agc.setNoiseInDb(DspK.agcNoiseInDb)
        agc.setNoiseOutDb(DspK.agcNoiseOutDb)
        agc.setAttackSamples(DspK.agcAttackSamples)
        agc.setHoldSamples(DspK.agcHoldSamples)
        agc.setEnabled(true)

        scratch.resize(bufferSize)

        configureDspChain()
        me.setMyCall(settings.myCallsign)
        me.setWpm(settings.wpm)
        me.setPitchHz(settings.pitchHz)
        modulator.setCarrierFreq(Float(settings.pitchHz))
    }

    deinit {
        realScratch.deallocate()
    }

    /// Runs `body` on the I/Q scratch buffer's two halves. The buffer is
    /// moved into a local for the duration, so the nested re/im access is
    /// not an exclusivity conflict on the stored property.
    private func withScratch(_ body: (UnsafeMutableBufferPointer<Float>,
                                      UnsafeMutableBufferPointer<Float>) -> Void) {
        var buf = ComplexBuf()
        swap(&buf, &scratch)
        buf.re.withUnsafeMutableBufferPointer { re in
            buf.im.withUnsafeMutableBufferPointer { im in
                body(re, im)
            }
        }
        swap(&buf, &scratch)
    }

    // MARK: Engine

    public var myCallsign: String { settings.myCallsign }
    public var heardCallsign: String { me.hisCall }
    public var playerSending: Bool { me.state == .sending }
    public var callsFromKeyer: Bool { settings.callsFromKeyer }
    func onPlayerStartedSending() { onMeStartedSending() }
    func onPlayerFinishedSending() { onMeFinishedSending() }
    /// Reads MyStation's message set directly, so the timing matches
    /// Pascal exactly: it resets when MyStation starts a fresh
    /// transmission from idle.
    var myLastMessage: MessageSet { me.msg }
    public var runMode: RunMode { settings.mode }
    public var lidsEnabled: Bool { settings.lids }
    public var flutterEnabled: Bool { settings.flutter }
    public var qsbEnabled: Bool { settings.qsb }
    public var targetWpm: Int { settings.wpm }
    public var activity: Int { settings.activity }
    /// Internal: a draw from outside the engine would shift every later
    /// draw and change the simulation.
    var random: Random { rng }

    public var player: MyStation { me }

    // MARK: Settings

    /// Diff-aware update: DSP state is only touched when the value that
    /// drives it changed (rebuilding on every change caused clicks).
    ///
    /// Like the C++, this replaces the whole struct, **including `mode`**:
    /// it does not run setRunMode's side effects (abort, clear, reset the
    /// clock), it only changes what the next block does. Read-modify-write
    /// (`var s = c.settings; ...; c.setSettings(s)`) keeps the mode.
    ///
    /// `wpm` must be at least 1: HST timing divides by it. The C++ has no
    /// guard; this traps instead of producing an infinite delay.
    public func setSettings(_ s: ContestSettings) {
        assertNotReentered()
        precondition(s.wpm >= 1, "ContestSettings.wpm must be >= 1, got \(s.wpm)")
        let prev = settings
        settings = s

        if prev.myCallsign != s.myCallsign {
            me.setMyCall(s.myCallsign)
        }
        if prev.wpm != s.wpm {
            me.setWpm(s.wpm)
        }
        if prev.pitchHz != s.pitchHz {
            // The C++ tests the same condition twice in a row (the first
            // guarded by `me_`, always set); one branch, same order.
            me.setPitchHz(s.pitchHz)
            modulator.setCarrierFreq(Float(s.pitchHz))
        }
        if prev.rxBandwidthHz != s.rxBandwidthHz {
            configureDspChain()
        }
    }

    public func setRunMode(_ mode: RunMode) {
        assertNotReentered()
        settings.mode = mode
        ended = false
        stopRequested = false

        if mode == .stop {
            // Pascal Run(rmStop) only disables audio output, so the clock
            // keeps showing the final contest time. The station list is
            // cleared here (Pascal clears it at the next Run) so nothing
            // keyed while stopped piles up.
            me.abortSend()
            stations.clear()
            return
        }

        // Pascal Run(<mode>): Tst.Me.AbortSend; Tst.BlockNumber := 0;
        // Tst.Me.Nr := 1; Log.Clear (which also clears Tst.Stations).
        // Starting a run keys nothing: in Pile-Up / WPX the player sends a
        // CQ to draw callers; Single / HST callers come from
        // spawnAutoCallers.
        me.abortSend()
        currentBlockIndex = 0
        currentMinute = 0.0
        me.setNr(1)
        stations.clear()
        lastLoggedCall = ""
        qsoCount = 0
    }

    // MARK: Player input (Pascal MainForm → Tst.Me)

    /// Pascal TMainForm.SendMsg: for msgHisCall the Call field's text
    /// becomes Me.HisCall (if not empty), then Me.SendMsg(msg).
    public func playerSendMessage(_ m: Message, callField: String = "") {
        assertNotReentered()
        if m == .hisCall && !callField.isEmpty {
            me.setHisCall(ByteString.asciiUppercased(callField))
        }
        me.sendMsg(m)
    }

    /// Pascal TMainForm.Edit1Change → Tst.Me.UpdateCallInMessage. Returns
    /// false when the edit could not be applied to a call being keyed or
    /// queued (the GUI then clears its CallSent flag).
    @discardableResult
    public func playerEditedCall(_ callField: String) -> Bool {
        assertNotReentered()
        return me.updateCallInMessage(ByteString.asciiUppercased(callField))
    }

    /// Pascal Log.SaveQso's side effects on the simulation: find a
    /// finished DX station with this call (DataToLastQso) and bump the
    /// player's serial number. `call` is the logged call, '?' stripped.
    public func qsoLogged(_ call: String) {
        assertNotReentered()
        lastLoggedCall = ByteString.asciiUppercased(call)
        qsoCount += 1
        matchLoggedQso()
        me.setNr(me.nr + 1)
    }

    /// Me.Msg flags the GUI needs when Esc aborts a send (Pascal checks
    /// msgHisCall / msgNR in Tst.Me.Msg to clear CallSent / NrSent).
    public func playerAbortSend() -> AbortInfo {
        assertNotReentered()
        let m = me.msg
        let info = AbortInfo(hadHisCall: m.contains(.hisCall), hadNr: m.contains(.nr))
        me.abortSend()
        return info
    }

    public func requestStop() { stopRequested = true }

    // MARK: Audio recording (Pascal File → Audio Recording Enabled)

    /// Starts writing every rendered block to a 16-bit mono WAV at
    /// `path`. Returns false (and records nothing) when the file cannot
    /// be opened.
    @discardableResult
    public func enableAudioRecording(path: String) -> Bool {
        assertNotReentered()
        if wavWriter == nil {
            wavWriter = WavWriter()
        }
        if wavWriter?.open(path: path) != true {
            wavWriter = nil
            return false
        }
        return true
    }

    public func disableAudioRecording() {
        assertNotReentered()
        wavWriter?.close()
        wavWriter = nil
    }

    // MARK: Internals

    private func matchLoggedQso() {
        if lastLoggedCall.isEmpty {
            return
        }
        for s in stations {
            guard let dx = s as? DxStation, !dx.shouldRemove,
                  dx.dxOperator.state == .done, dx.myCall == lastLoggedCall else {
                continue
            }
            // TDxStation.DataToLastQso, then Free.
            if let onQsoCompleted {
                let qso = CompletedQso(call: dx.myCall, rst: dx.rst, nr: dx.nr,
                                       minute: currentMinute)
                withStationCallbackGuard { onQsoCompleted(qso) }
            }
            dx.release()
        }
    }

    private func configureDspChain() {
        // Pascal: Filt.Points = round(0.7 * SR / BW); Passes = 3;
        // GainDb = 10*log10(500/BW). Resets the filter's delay line, which
        // is what we want when bandwidth shifts.
        let bw = max(Float(1.0), Float(settings.rxBandwidthHz))
        let points = max(1, delphiRound(DspK.filterPointsRatio * Float(AudioK.sampleRate) / bw))
        let gainDb: Float = 10.0 * log10(DspK.filterGainRefBw / bw)
        filter.configure(points: points, passes: DspK.filterPasses,
                         samplesInInput: bufferSize, gainDb: gainDb)
        // AGC parameters are constants and never change after init.
    }

    /// Pascal: TContest.OnMeFinishedSending. Poisson-spawns callers when
    /// the player just sent CQ (or finished a QSO with TU + MyCall), then
    /// broadcasts evMeFinished to every station.
    private func onMeFinishedSending() {
        let heard = me.msg
        let playerCq = heard.contains(.cq)
        // 1.68: TU + MyCall after a QSO counts as a CQ (QsoList <> nil).
        let playerEndedQso = qsoCount > 0 && heard.contains(.tu) && heard.contains(.myCall)
        let spawnEligible = settings.mode != .single && settings.mode != .hst
        if spawnEligible && (playerCq || playerEndedQso) {
            // Pascal: for i := 1 to RndPoisson(Activity / 2) do AddCaller.
            let lambda = Float(settings.activity) / SimK.callerSpawnRateActivityDivisor
            let spawnCount = rng.poisson(lambda)
            for _ in 0..<spawnCount {
                stations.addCaller(self, callsignSource.pickCall(rng))
            }
        }
        for s in stations {
            s.processEvent(.meFinished)
        }
    }

    /// Pascal: TContest.OnMeStartedSending.
    private func onMeStartedSending() {
        for s in stations {
            s.processEvent(.meStarted)
        }
    }

    private func mixStationsIntoComplex() {
        // Pascal walks `i = 0..High(Blk)` and computes:
        //   Bfo = Station.Bfo - RitPhase - i * 2π * RIT / SR
        // snapshotting the station's phase at i=0 and advancing locally.
        let twoPi = MathK.twoPi
        let sr = Double(AudioK.sampleRate)
        let ritRadPerSample = twoPi * Double(settings.ritHz) / sr

        for s in stations {
            if s.state != .sending {
                continue
            }
            realScratch.update(repeating: 0.0)
            let got = s.getBlock(realScratch)
            if got == 0 {
                continue
            }
            let bfoStart = s.bfoPhase
            let pitchRadPerSample = twoPi * Double(s.pitchHz) / sr
            var phase = bfoStart
            let ritStart = ritPhase
            withScratch { re, im in
                for i in 0..<got {
                    let bfo = phase - ritStart - Double(i) * ritRadPerSample
                    let sample = realScratch[i]
                    // C++ std::cos/std::sin of the same angle → sincos.
                    let sc = sinCos(bfo)
                    re[i] += Float(Double(sample) * sc.cos)
                    im[i] -= Float(Double(sample) * sc.sin)
                    phase += pitchRadPerSample
                }
            }
            // Keep the station's internal BFO consistent.
            for _ in 0..<got {
                s.tickBfoPhase()
            }
        }

        // Advance the RIT phase accumulator for the next block.
        ritPhase += Double(bufferSize) * ritRadPerSample
        while ritPhase > twoPi {
            ritPhase -= twoPi
        }
        while ritPhase < -twoPi {
            ritPhase += twoPi
        }
    }

    private func applySelfMonitor() {
        if me.state != .sending {
            return
        }
        realScratch.update(repeating: 0.0)
        // getBlock may fire onPlayerPieceFinished.
        var got = 0
        withStationCallbackGuard { got = me.getBlock(realScratch) }
        if got == 0 {
            return
        }
        // Smg = 10^((slider - 0.75) * 4). Pascal: Contest.pas::GetAudio.
        let smg = pow(Float(10.0),
                      (settings.selfMonGain01 - DspK.selfMonGainSliderZero) * DspK.selfMonGainScale)
        let amp = me.amplitude

        withScratch { re, im in
            if settings.qsk {
                // QSK: duck the external signal proportional to our own
                // transmission envelope. Pascal:
                //   if Rfg > (1 - blk/amp) then Rfg := 1 - blk/amp
                //   else Rfg := Rfg*0.997 + 0.003
                //   Re/Im[i] = Smg*blk + Rfg*Re/Im[i]
                for i in 0..<got {
                    let blk = realScratch[i]
                    let target: Float = 1.0 - blk / amp
                    if qskRfg > target {
                        qskRfg = target
                    } else {
                        qskRfg = qskRfg * DspK.qskAttackCoeff + DspK.qskReleaseAdd
                    }
                    re[i] = smg * blk + qskRfg * re[i]
                    im[i] = smg * blk + qskRfg * im[i]
                }
            } else {
                // Non-QSK: the external signal is replaced while keying.
                for i in 0..<got {
                    re[i] = smg * realScratch[i]
                    im[i] = smg * realScratch[i]
                }
            }
        }
    }

    private func applyEndOfSession() {
        if ended {
            return
        }
        let durationSec = Float(settings.durationMinutes) * 60.0
        let elapsed = Float(AudioK.blocksToSeconds(Double(currentBlockIndex), bufSize: bufferSize))
        if elapsed >= durationSec || stopRequested {
            ended = true
            let mode = settings.mode
            let byUser = stopRequested
            setRunMode(.stop)
            onEndOfSession?(mode, byUser)
        }
    }

    private func spawnAutoCallers() {
        // Pascal Contest.pas::GetAudio tail end:
        //   rmSingle and DxCount=0 → spawn one caller
        //   rmHst and DxCount<Activity → top up to Activity
        // In both cases Pascal first sets `Me.Msg := [msgCQ]` and then hands
        // each new caller an evMeFinished, so it behaves as if it just heard
        // a CQ (NeedPrevEnd → NeedQso) and calls after its send delay.
        var cq = MessageSet()
        cq.insert(.cq)
        if settings.mode == .single && stations.dxCount == 0 {
            me.setMsg(cq)
            stations.addCaller(self, callsignSource.pickCall(rng)).processEvent(.meFinished)
        } else if settings.mode == .hst {
            let needed = settings.activity - stations.dxCount
            if needed > 0 {
                me.setMsg(cq)
            }
            var i = 0
            while i < needed {
                let call = callsignSource.pickAndRemoveCall(rng)
                stations.addCaller(self, call).processEvent(.meFinished)
                i += 1
            }
        }
    }

    private func tickAndSweep() {
        // Pascal GetAudio: Me.Tick, then every station's Tick (last to
        // first). The player's start/finish events fire synchronously from
        // MyStation (sendText / MsgSent), as in Pascal.
        me.tick()
        var i = stations.count
        while i > 0 {
            i -= 1
            stations[i].tick()
        }

        // "if DX is done, write to log and kill" — the DX matching the last
        // logged QSO hands over its record, then goes away.
        matchLoggedQso()

        stations.sweep()
    }

    /// Render one audio block into `out` (at least `bufferSize` samples).
    /// Returns the number of samples written (0 if `out` is too short).
    @discardableResult
    public func renderNextBlock(into out: UnsafeMutableBufferPointer<Float>) -> Int {
        assertNotReentered()
        if out.count < bufferSize {
            return 0
        }
        if settings.mode == .stop {
            for i in 0..<bufferSize { out[i] = 0.0 }
            return bufferSize
        }

        currentBlockIndex += 1
        currentMinute = Float(AudioK.blocksToSeconds(Double(currentBlockIndex),
                                                     bufSize: bufferSize) / 60.0)

        // Pascal: skip first 6 blocks to mask startup pop.
        if currentBlockIndex < AudioK.startupSkipBlocks {
            for i in 0..<bufferSize { out[i] = 0.0 }
            return bufferSize
        }

        let n = bufferSize
        withScratch { re, im in
            // 1) Complex noise. Pascal: 3 · NOISEAMP · (R - 0.5).
            for i in 0..<n {
                re[i] = DspK.noiseChannelGainMul * DspK.noiseAmp * (rng.uniform01() - 0.5)
                im[i] = DspK.noiseChannelGainMul * DspK.noiseAmp * (rng.uniform01() - 0.5)
            }
            // 2) QRN: per-sample spike.
            if settings.qrn {
                for i in 0..<n where rng.uniform01() < DspK.qrnSpikePerSampleProb {
                    re[i] = DspK.qrnSpikeAmpMul * DspK.noiseAmp * (rng.uniform01() - 0.5)
                }
            }
        }
        // 2b) QRN burst spawn.
        if settings.qrn && rng.uniform01() < DspK.qrnBurstPerBlockProb {
            stations.addQrn(self)
        }

        // 3) QRM: per-block spawn.
        if settings.qrm && rng.uniform01() < DspK.qrmSpawnPerBlockProb {
            stations.addQrm(self, callsignSource.pickCall(rng))
        }

        // 4) Mix every active station's keying into the I/Q buffer.
        mixStationsIntoComplex()

        // 5) Player self-monitor.
        applySelfMonitor()

        // 6) Ping-pong LPF over the complex buffer.
        filter.process(&scratch)

        // 7) Modulator: complex → real.
        let real = UnsafeMutableBufferPointer(rebasing: realScratch[0..<n])
        modulator.modulate(scratch, real)

        // 8) AGC.
        agc.process(real)

        // 9) Scale to ±1 Float-PCM and copy to caller.
        for i in 0..<n {
            out[i] = real[i] * floatPcmScale
        }

        // 9b) Pascal "Save WAV" tap: the same final-mixed signal the audio
        // thread plays.
        if let w = wavWriter {
            w.append(normalized: UnsafeBufferPointer(rebasing: out[0..<n]))
        }

        // 10) Per-block bookkeeping: tick + sweep, auto-spawn, end check.
        tickAndSweep()
        spawnAutoCallers()
        applyEndOfSession()

        return n
    }

    /// Array convenience for renderNextBlock(into:).
    @discardableResult
    public func renderNextBlock(_ out: inout [Float]) -> Int {
        out.withUnsafeMutableBufferPointer { renderNextBlock(into: $0) }
    }
}
