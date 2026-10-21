// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/audio/AudioEngine (the `mr-audio` side). The C++ runs its
// own QThread that polls the ring every 8 ms and pushes into a
// QAudioSink; here Core Audio's render thread pulls directly from the
// ring through an AVAudioSourceNode, so there is no audio thread of our
// own and no polling.
//
// Format: the source node outputs mono Float32 at 11025 Hz (Pascal
// DEFAULTRATE, the C++ makeFormat()); AVAudioEngine's mixer resamples
// to the device rate, as QAudioSink/Core Audio did for the C++.
//
// Buffering / latency: the C++ queues up to kAudioRingFrames (3)
// blocks in the ring plus a 4-block (2048-sample, ~186 ms) QAudioSink
// buffer, because its timer-driven push model needed slack to absorb
// pump jitter. A pull model doesn't: the render thread consumes on
// demand, so the only buffering is the ring (3 x 512 samples ≈ 139 ms
// at 11025 Hz, same depth as the C++ ring) plus the device I/O buffer
// (typically 512 frames at 48 kHz ≈ 11 ms) and the resampler. That keeps
// the keying-to-ear latency below the C++ port's while leaving the sim
// thread nearly three blocks of headroom.
//
// Device / configuration changes: AVAudioEngine stops itself and posts
// AVAudioEngineConfigurationChange; we reconnect the source node (the
// mixer's output format may have changed) and restart if we were
// running. The partially played block and the ring survive the restart.

import AVFAudio
import Foundation
import MRCore

@MainActor
public final class AudioOutput {
    public let source: RingPlaybackSource
    public let engine = AVAudioEngine()
    public let sourceNode: AVAudioSourceNode
    /// Mono Float32, non-interleaved, 11025 Hz.
    public let format: AVAudioFormat

    /// Times the engine was successfully restarted after a
    /// configuration change.
    public private(set) var configurationRestarts = 0
    /// Times a restart after a configuration change failed (no usable
    /// device at that moment). The output stays stopped until a later
    /// configuration change succeeds or start() is called again.
    public private(set) var configurationRestartFailures = 0
    /// True while the engine is actually running.
    public private(set) var isRunning = false
    /// The caller's intent: set by start(), cleared by stop(). A
    /// configuration change restarts the engine only while this is set,
    /// so a failed restart is retried on the next change.
    public private(set) var wantsRunning = false

    // nonisolated(unsafe): deinit is nonisolated and must read the token
    // to unregister it. It is written exactly once, in init (before the
    // object is shared), and only read again in deinit, when no other
    // reference exists, so there is no concurrent access.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    public init(ring: AudioBlockRing, sampleRate: Double = Double(AudioK.sampleRate)) {
        source = RingPlaybackSource(ring: ring)
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 1, interleaved: false)!
        sourceNode = Self.makeSourceNode(format: format, source: source)
        engine.attach(sourceNode)
        connectGraph()
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public var underrunCount: UInt64 { source.underrunCount }
    public var blocksEmitted: UInt64 { source.blocksEmitted }

    /// Starts pulling from the ring. Throws if there is no usable output
    /// device; the ring and counters are unaffected.
    public func start() throws {
        guard !isRunning else { return }
        engine.prepare()
        try engine.start()
        isRunning = true
        wantsRunning = true
    }

    public func stop() {
        wantsRunning = false
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    private func connectGraph() {
        engine.disconnectNodeOutput(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }

    /// AVAudioEngineConfigurationChange handler (internal for tests).
    func handleConfigurationChange() {
        // The engine has already stopped itself.
        isRunning = false
        connectGraph()
        guard wantsRunning else { return }
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            configurationRestarts += 1
        } catch {
            // No device right now; a later configuration change (device
            // reappears) brings us back here and retries.
            configurationRestartFailures += 1
        }
    }

    /// Built outside the main actor so the render block carries no actor
    /// isolation (it runs on Core Audio's real-time thread). The block
    /// captures only `source` (immutable reference, retained once here).
    private nonisolated static func makeSourceNode(format: AVAudioFormat,
                                                   source: RingPlaybackSource) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            Self.render(source: source, frameCount: Int(frameCount),
                        bufferList: audioBufferList, isSilence: isSilence)
            return noErr
        }
    }

    /// The render callback body, as a plain function over an
    /// AudioBufferList (tested directly). Channel 0 gets the ring's
    /// samples (at most its byte capacity); any further buffers (none for
    /// our mono format) get a copy, each truncated to its own capacity.
    /// An empty buffer list, or a first buffer without data, is left
    /// untouched and consumes nothing from the ring.
    public nonisolated static func render(source: RingPlaybackSource, frameCount: Int,
                                          bufferList: UnsafeMutablePointer<AudioBufferList>,
                                          isSilence: UnsafeMutablePointer<ObjCBool>) {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard abl.count > 0, let first = abl[0].mData?.assumingMemoryBound(to: Float.self) else {
            return
        }
        let capacity = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
        let n = max(0, min(frameCount, capacity))
        let silent = source.render(into: UnsafeMutableBufferPointer(start: first, count: n))
        for i in 1..<abl.count {
            if let d = abl[i].mData?.assumingMemoryBound(to: Float.self) {
                d.update(from: first, count: min(n, Int(abl[i].mDataByteSize) / MemoryLayout<Float>.size))
            }
        }
        isSilence.pointee = ObjCBool(silent)
    }
}
