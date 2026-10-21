// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The pull logic of src/audio/AudioEngine.cpp (AudioEngine::pump),
// separated from AVAudioEngine so it can be tested without a device.
//
// Core Audio asks for `frameCount` samples per render call, a number
// unrelated to the simulator's 512-sample blocks (and, after
// resampling to the device rate, not even constant). Like the C++
// `pending_` / `pendingByteOffset_`, we keep the partially consumed
// block: it simply stays at the ring's head and `readOffset` records how
// far into it we are; it is released only when fully played.
//
// If the producer has not delivered a block in time, the remainder of
// the request is filled with silence and `underrunCount` is bumped once
// per render call (C++: one bump per starved pump tick).
//
// Real-time safety: render(into:) touches only preallocated memory,
// the ring's atomics and two relaxed atomic counters. No allocation,
// locks, ObjC messaging or ARC retain/release (all stored properties are
// `let` references captured once). The read offset lives in raw memory
// allocated in init rather than in a stored `var`, so the render path
// has no dynamic exclusivity checks (swift_beginAccess) either.

import Synchronization

public final class RingPlaybackSource: @unchecked Sendable {
    // @unchecked: `readOffset` is touched only by the render thread
    // (one render call at a time, guaranteed by Core Audio); everything
    // else is immutable or atomic.

    public let ring: AudioBlockRing
    /// Samples of the head block already played. Render thread only.
    private let readOffset: UnsafeMutablePointer<Int>
    private let underruns = Atomic<UInt64>(0)
    private let blocksPlayed = Atomic<UInt64>(0)

    public init(ring: AudioBlockRing) {
        self.ring = ring
        readOffset = .allocate(capacity: 1)
        readOffset.initialize(to: 0)
    }

    deinit {
        readOffset.deallocate()
    }

    /// Render calls that ran out of blocks (C++ AudioEngine::underrunCount).
    public var underrunCount: UInt64 { underruns.load(ordering: .relaxed) }
    /// Blocks fully played (C++ AudioEngine::framesEmitted).
    public var blocksEmitted: UInt64 { blocksPlayed.load(ordering: .relaxed) }

    /// Fills `out` from the ring. Returns true if the whole buffer is
    /// silence because the ring was empty (Core Audio's `isSilence` hint).
    @discardableResult
    public func render(into out: UnsafeMutableBufferPointer<Float>) -> Bool {
        guard let dst = out.baseAddress, out.count > 0 else { return false }
        let total = out.count
        var filled = 0
        var offset = readOffset.pointee
        defer { readOffset.pointee = offset }
        while filled < total {
            guard let block = ring.readableBlock() else {
                (dst + filled).update(repeating: 0, count: total - filled)
                underruns.add(1, ordering: .relaxed)
                return filled == 0
            }
            let available = block.count - offset
            let n = min(available, total - filled)
            if n > 0, let src = block.baseAddress {
                (dst + filled).update(from: src + offset, count: n)
                filled += n
                offset += n
            }
            if offset >= block.count {
                ring.releaseBlock()
                offset = 0
                blocksPlayed.add(1, ordering: .relaxed)
            }
        }
        return false
    }
}
