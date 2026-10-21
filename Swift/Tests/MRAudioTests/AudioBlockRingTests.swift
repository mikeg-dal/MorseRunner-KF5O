// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
@testable import MRAudio
import Testing

private func pushBlock(_ ring: AudioBlockRing, value: Float, count: Int? = nil) -> Bool {
    ring.write { slot in
        let n = count ?? slot.count
        for i in 0..<n { slot[i] = value + Float(i) }
        return n
    }
}

@Suite struct AudioBlockRingTests {
    @Test func emptyRingHasNothingToRead() {
        let ring = AudioBlockRing(capacity: 3, blockSize: 8)
        #expect(ring.isEmpty)
        #expect(ring.readableBlock() == nil)
        var out = [Float](repeating: 0, count: 8)
        #expect(out.withUnsafeMutableBufferPointer { ring.pop(into: $0) } == nil)
    }

    @Test func fillsToCapacityThenRejects() {
        let ring = AudioBlockRing(capacity: 3, blockSize: 4)
        #expect(pushBlock(ring, value: 0))
        #expect(pushBlock(ring, value: 10))
        #expect(pushBlock(ring, value: 20))
        #expect(ring.isFull)
        var called = false
        let ok = ring.write { _ in called = true; return 4 }
        #expect(!ok && !called)
        #expect(ring.count == 3)
    }

    @Test func fifoOrderAcrossManyWraparounds() {
        let ring = AudioBlockRing(capacity: 3, blockSize: 4)
        var out = [Float](repeating: -1, count: 4)
        var nextIn = 0, nextOut = 0
        // Interleave pushes/pops with varying fill levels so head/tail
        // wrap the 3 slots many times.
        for round in 0..<200 {
            let pushes = round % 3 + 1
            for _ in 0..<pushes where !ring.isFull {
                #expect(pushBlock(ring, value: Float(nextIn * 100)))
                nextIn += 1
            }
            let pops = (round + 1) % 3 + 1
            for _ in 0..<pops {
                guard let n = out.withUnsafeMutableBufferPointer({ ring.pop(into: $0) }) else { break }
                #expect(n == 4)
                #expect(out == [0, 1, 2, 3].map { Float(nextOut * 100) + $0 })
                nextOut += 1
            }
        }
        #expect(nextOut > 150)
        #expect(ring.count == nextIn - nextOut)
    }

    @Test func shortBlocksKeepTheirCount() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        #expect(pushBlock(ring, value: 1, count: 3))
        #expect(ring.write { _ in 99 })                // clamped to blockSize
        #expect(ring.readableBlock()?.count == 3)
        ring.releaseBlock()
        #expect(ring.readableBlock()?.count == 8)
    }

    @Test func pushCopiesSamples() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 4)
        let src: [Float] = [1, 2, 3, 4, 5]
        #expect(src.withUnsafeBufferPointer { ring.push($0) })
        #expect(Array(ring.readableBlock()!) == [1, 2, 3, 4])
    }

    @Test func countAndFlagsTrackFillLevel() {
        let ring = AudioBlockRing(capacity: 3, blockSize: 4)
        #expect(ring.count == 0 && ring.isEmpty && !ring.isFull)
        #expect(pushBlock(ring, value: 0))
        #expect(ring.count == 1 && !ring.isEmpty && !ring.isFull)
        #expect(pushBlock(ring, value: 0))
        #expect(pushBlock(ring, value: 0))
        #expect(ring.count == 3 && ring.isFull)
        ring.releaseBlock()
        #expect(ring.count == 2 && !ring.isFull)
    }

    @Test func pushOfAnEmptyBufferPublishesAZeroLengthBlock() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 4)
        #expect(ring.push(UnsafeBufferPointer(start: nil, count: 0)))
        #expect(ring.count == 1)
        #expect(ring.readableBlock()?.count == 0)
    }

    @Test func popIntoAShorterBufferCopiesAPrefixAndReleasesTheBlock() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        #expect(pushBlock(ring, value: 10))
        #expect(pushBlock(ring, value: 20))
        var out = [Float](repeating: -1, count: 3)
        let n = out.withUnsafeMutableBufferPointer { ring.pop(into: $0) }
        #expect(n == 8)                                 // the block's count, not out.count
        #expect(out == [10, 11, 12])
        #expect(ring.count == 1)                        // whole block released
        #expect(ring.readableBlock()?.first == 20)
    }

    @Test func popIntoAnEmptyBufferStillReleases() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 4)
        #expect(pushBlock(ring, value: 0))
        let n = ring.pop(into: UnsafeMutableBufferPointer(start: nil, count: 0))
        #expect(n == 4)
        #expect(ring.isEmpty)
    }

    @Test func waitForSpaceReturnsImmediatelyWhenThereIsRoom() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 4)
        #expect(pushBlock(ring, value: 0))              // one slot still free
        let t0 = ContinuousClock.now
        ring.waitForSpace(timeoutNanoseconds: 10_000_000_000)
        #expect(ContinuousClock.now - t0 < .seconds(2))
    }

    @Test func waitForSpaceTimesOutWhenFull() {
        let ring = AudioBlockRing(capacity: 1, blockSize: 4)
        #expect(pushBlock(ring, value: 0))
        let t0 = ContinuousClock.now
        ring.waitForSpace(timeoutNanoseconds: 30_000_000)
        let dt = ContinuousClock.now - t0
        #expect(dt >= .milliseconds(25))
        #expect(dt < .seconds(5))
        #expect(ring.isFull)
    }

    @Test(.timeLimit(.minutes(1)))
    func wakeProducerEndsAParkedWait() {
        let ring = AudioBlockRing(capacity: 1, blockSize: 4)
        #expect(pushBlock(ring, value: 0))
        let waker = Thread {
            usleep(50_000)
            ring.wakeProducer()
        }
        waker.start()
        let t0 = ContinuousClock.now
        ring.waitForSpace(timeoutNanoseconds: 30_000_000_000)
        #expect(ContinuousClock.now - t0 < .seconds(20))
        #expect(ring.isFull)                            // woken without space
    }

    @Test(.timeLimit(.minutes(1)))
    func releaseBlockWakesAParkedProducer() {
        let ring = AudioBlockRing(capacity: 1, blockSize: 4)
        #expect(pushBlock(ring, value: 0))
        let consumer = Thread {
            usleep(50_000)
            ring.releaseBlock()
        }
        consumer.start()
        let t0 = ContinuousClock.now
        while ring.isFull {
            ring.waitForSpace(timeoutNanoseconds: 30_000_000_000)
        }
        #expect(ContinuousClock.now - t0 < .seconds(20))
        #expect(ring.isEmpty)
    }

    /// Producer and consumer on separate threads, the producer parking on
    /// the ring's semaphore when full. Every sample must arrive in order.
    /// Run under TSan: swift test --sanitize=thread --filter MRAudioTests
    @Test(.timeLimit(.minutes(1)))
    func twoThreadStress() async {
        let ring = AudioBlockRing(capacity: 3, blockSize: 64)
        let blocks = 20_000
        let producer = Thread {
            var k = 0
            while k < blocks {
                let ok = ring.write { slot in
                    for i in 0..<slot.count { slot[i] = Float(k * 64 + i) }
                    return slot.count
                }
                if ok { k += 1 } else { ring.waitForSpace(timeoutNanoseconds: 5_000_000) }
            }
        }
        let errors = await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            let consumer = Thread {
                var expected: Float = 0, errors = 0, got = 0
                while got < blocks {
                    guard let b = ring.readableBlock() else {
                        sched_yield()
                        continue
                    }
                    for s in b { if s != expected { errors += 1 }; expected += 1 }
                    ring.releaseBlock()
                    got += 1
                }
                cont.resume(returning: errors)
            }
            consumer.start()
            producer.start()
        }
        #expect(errors == 0)
        #expect(ring.isEmpty)
    }
}
