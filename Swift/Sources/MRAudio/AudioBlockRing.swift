// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of src/audio/AudioRing.h + AudioFrame.h: the single SPSC
// hand-off between the simulation thread (producer, `mr-sim`) and the
// Core Audio render thread (consumer). The C++ wraps
// moodycamel::ReaderWriterQueue<AudioFrame>, pre-sized so it never
// grows; this is a hand-rolled equivalent on Swift `Synchronization`.
//
// Real-time safety (consumer side):
//  - All sample storage is allocated once in init: `capacity` slots of
//    `blockSize` Floats each, plus a per-slot valid-sample count. No
//    allocation, locking, ARC traffic or Swift runtime calls happen in
//    readableBlock()/releaseBlock().
//  - `head` and `tail` are monotonically increasing counters (slot =
//    counter % capacity). The producer publishes a filled slot with a
//    releasing store of `tail`; the consumer observes it with an
//    acquiring load, and returns the slot with a releasing store of
//    `head`. That pair is the only synchronisation the data needs.
//  - Producer back-pressure: when the ring is full the producer may park
//    in waitForSpace(). The consumer signals the semaphore only if the
//    producer announced it is parked (an atomic flag exchanged back to
//    false), so in steady state the render thread makes no syscall at
//    all; when it does, DispatchSemaphore.signal is a non-blocking
//    atomic + mach semaphore_signal (a plain C call, no ObjC message),
//    the same wake-up primitive Apple's and JUCE's real-time code use.
//    The semaphore is held through an Unmanaged reference retained once
//    in init and released in deinit, and signalled through
//    _withUnsafeGuaranteedRef, so the render thread does no
//    retain/release on it either.
//  - Wake-up handshake (Dekker pattern): the producer stores
//    producerParked = true and then loads `head`; the consumer stores
//    `head` and then exchanges producerParked. All four operations are
//    sequentially consistent, so at least one side sees the other's
//    write: either the producer sees the freed slot and does not sleep,
//    or the consumer sees the flag and signals. (An acquire load of
//    `head` would not be enough: store→load reordering is allowed
//    between a seq_cst store and a weaker load.)

import Dispatch
import Synchronization

public final class AudioBlockRing: @unchecked Sendable {
    // @unchecked: `storage`/`counts` are raw memory whose per-slot
    // ownership alternates between exactly one producer and one consumer
    // thread, handed over by the head/tail acquire/release pairs.

    public let capacity: Int
    public let blockSize: Int

    private let storage: UnsafeMutablePointer<Float>
    private let counts: UnsafeMutablePointer<Int>
    /// Next slot the consumer reads (only the consumer stores it).
    private let head = Atomic<Int>(0)
    /// Next slot the producer writes (only the producer stores it).
    private let tail = Atomic<Int>(0)
    /// True while the producer is parked in waitForSpace().
    private let producerParked = Atomic<Bool>(false)
    /// Retained once in init, released in deinit (see header comment).
    private let space: Unmanaged<DispatchSemaphore>

    /// - Parameters:
    ///   - capacity: number of blocks; C++ kAudioRingFrames (3) by default.
    ///   - blockSize: samples per block; Pascal BufSize (512) by default.
    public init(capacity: Int = 3, blockSize: Int = 512) {
        precondition(capacity > 0 && blockSize > 0)
        self.capacity = capacity
        self.blockSize = blockSize
        storage = .allocate(capacity: capacity * blockSize)
        storage.initialize(repeating: 0, count: capacity * blockSize)
        counts = .allocate(capacity: capacity)
        counts.initialize(repeating: 0, count: capacity)
        space = .passRetained(DispatchSemaphore(value: 0))
    }

    deinit {
        storage.deallocate()
        counts.deallocate()
        space.release()
    }

    // MARK: - Either thread (approximate when called from the other side)

    /// Number of filled blocks waiting to be consumed, in 0...capacity.
    ///
    /// Exact when called from the producer or the consumer while the
    /// other side is idle; otherwise a snapshot. `head` is loaded before
    /// `tail`, so the result never goes negative: called from the
    /// producer (exact `tail`, possibly stale `head`) it can only
    /// over-report, which is the safe direction for "is there room?";
    /// called from the consumer (exact `head`) it can only under-report
    /// blocks published after the load. Any other thread gets a value
    /// that was true at some instant between the two loads, clamped to
    /// `capacity`.
    public var count: Int {
        let h = head.load(ordering: .acquiring)
        let t = tail.load(ordering: .acquiring)
        return min(max(t &- h, 0), capacity)
    }

    public var isEmpty: Bool { count == 0 }
    public var isFull: Bool { count >= capacity }

    // MARK: - Producer

    /// Renders directly into the next free slot. `body` receives the
    /// whole `blockSize` slot and returns how many samples it filled
    /// (clamped to 0...blockSize); the slot is then published. Returns
    /// false, without calling `body`, if the ring is full.
    @discardableResult
    public func write(_ body: (UnsafeMutableBufferPointer<Float>) throws -> Int) rethrows -> Bool {
        let t = tail.load(ordering: .relaxed)            // we are its only writer
        let h = head.load(ordering: .acquiring)          // slot freed by consumer
        if t &- h >= capacity { return false }
        let slot = t % capacity
        let buf = UnsafeMutableBufferPointer(start: storage + slot * blockSize, count: blockSize)
        let n = try body(buf)
        counts[slot] = min(max(n, 0), blockSize)
        tail.store(t &+ 1, ordering: .releasing)
        return true
    }

    /// Copies `samples` (at most `blockSize` of them) into a new block.
    @discardableResult
    public func push(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        write { slot in
            let n = min(samples.count, slot.count)
            if n > 0, let src = samples.baseAddress {
                slot.baseAddress!.update(from: src, count: n)
            }
            return n
        }
    }

    /// Parks the producer until the consumer frees a slot, wakeProducer()
    /// is called, or `timeoutNanoseconds` elapses. Returns immediately if
    /// the ring already has space. Spurious returns are possible; callers
    /// re-check their conditions in a loop.
    /// Producer thread only.
    public func waitForSpace(timeoutNanoseconds: UInt64) {
        producerParked.store(true, ordering: .sequentiallyConsistent)
        // Re-check after announcing, with a seq_cst load of `head`: pairs
        // with the consumer's seq_cst store(head) → exchange(producerParked)
        // so a release that races with parking is never missed.
        let t = tail.load(ordering: .relaxed)            // we are its only writer
        let h = head.load(ordering: .sequentiallyConsistent)
        if t &- h < capacity {
            producerParked.store(false, ordering: .sequentiallyConsistent)
            return
        }
        _ = space.takeUnretainedValue()
            .wait(timeout: .now() + .nanoseconds(Int(clamping: timeoutNanoseconds)))
        producerParked.store(false, ordering: .sequentiallyConsistent)
    }

    /// Wakes a producer parked in waitForSpace() (used for commands/stop).
    /// Any thread. If the producer is not parked, its next waitForSpace()
    /// returns immediately once (a spurious return, see above).
    public func wakeProducer() {
        _ = space._withUnsafeGuaranteedRef { $0.signal() }
    }

    // MARK: - Consumer (real-time safe)

    /// The oldest filled block, or nil if the ring is empty. The buffer
    /// stays valid until releaseBlock().
    @inline(__always)
    public func readableBlock() -> UnsafeBufferPointer<Float>? {
        let h = head.load(ordering: .relaxed)            // we are its only writer
        let t = tail.load(ordering: .acquiring)          // block published by producer
        if t == h { return nil }
        let slot = h % capacity
        return UnsafeBufferPointer(start: storage + slot * blockSize, count: counts[slot])
    }

    /// Returns the block obtained from readableBlock() to the producer.
    @inline(__always)
    public func releaseBlock() {
        let h = head.load(ordering: .relaxed)
        head.store(h &+ 1, ordering: .sequentiallyConsistent)
        if producerParked.exchange(false, ordering: .sequentiallyConsistent) {
            _ = space._withUnsafeGuaranteedRef { $0.signal() }
        }
    }

    /// Copies the oldest block into `out` (up to out.count samples) and
    /// releases it. Returns the block's sample count, or nil if empty.
    public func pop(into out: UnsafeMutableBufferPointer<Float>) -> Int? {
        guard let block = readableBlock() else { return nil }
        let n = min(block.count, out.count)
        if n > 0 { out.baseAddress!.update(from: block.baseAddress!, count: n) }
        releaseBlock()
        return block.count
    }
}
