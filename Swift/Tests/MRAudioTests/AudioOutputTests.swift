// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AVFAudio
import CoreAudio
@testable import MRAudio
import Testing

/// True when Core Audio reports a default output device.
private let hasDefaultOutputDevice: Bool = {
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                            0, nil, &size, &device)
    return status == noErr && device != kAudioObjectUnknown
}()

@MainActor
@Suite struct AudioOutputTests {
    @Test func sourceNodeIs11025Mono() {
        let out = AudioOutput(ring: AudioBlockRing())
        let f = out.sourceNode.outputFormat(forBus: 0)
        #expect(f.sampleRate == 11025)
        #expect(f.channelCount == 1)
        #expect(f.commonFormat == .pcmFormatFloat32)
        #expect(!out.isRunning && !out.wantsRunning)
    }

    /// A configuration change while stopped reconnects the graph but must
    /// not start the engine (no device needed, nothing audible).
    @Test func configurationChangeWhileStoppedDoesNotStart() {
        let out = AudioOutput(ring: AudioBlockRing())
        out.handleConfigurationChange()
        #expect(!out.isRunning && !out.engine.isRunning)
        #expect(out.configurationRestarts == 0 && out.configurationRestartFailures == 0)
        #expect(out.sourceNode.outputFormat(forBus: 0).sampleRate == 11025)
    }

    @Test func stopWithoutStartIsHarmless() {
        let out = AudioOutput(ring: AudioBlockRing())
        out.stop()
        #expect(!out.isRunning && !out.wantsRunning)
    }

    /// Starts and stops the engine with the mixer muted and an empty ring,
    /// so it can only ever render silence. Needs an output device.
    @Test(.enabled(if: hasDefaultOutputDevice, "needs a default output device"))
    func engineStartsAndStops() throws {
        let out = AudioOutput(ring: AudioBlockRing())
        out.engine.mainMixerNode.outputVolume = 0
        try out.start()
        #expect(out.isRunning && out.wantsRunning)
        try out.start()                                  // idempotent
        // Simulate a device change: the engine stops itself, then posts.
        out.engine.stop()
        out.handleConfigurationChange()
        #expect(out.isRunning == out.engine.isRunning)
        #expect(out.configurationRestarts + out.configurationRestartFailures == 1)
        out.stop()
        #expect(!out.isRunning && !out.wantsRunning && !out.engine.isRunning)
    }
}
