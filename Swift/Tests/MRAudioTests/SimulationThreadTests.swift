// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
@testable import MRAudio
import Synchronization
import Testing

/// Counters a FakeRenderer reports through (shared with the test).
private final class Probe: Sendable {
    /// Renders currently in progress (must never exceed 1).
    let inside = Atomic<Int>(0)
    let overlaps = Atomic<Int>(0)
    let deinits = Atomic<Int>(0)
}

/// Writes a running sample counter; records commands in order. Touched
/// only on the sim thread once handed over.
private final class FakeRenderer: BlockRenderer {
    let probe: Probe
    var next: Float = 0
    var log: [Int] = []
    var returnZero = false

    init(probe: Probe = Probe()) { self.probe = probe }
    deinit { probe.deinits.add(1, ordering: .relaxed) }

    func renderNextBlock(into buffer: UnsafeMutableBufferPointer<Float>) -> Int {
        if probe.inside.add(1, ordering: .sequentiallyConsistent).newValue != 1 {
            probe.overlaps.add(1, ordering: .relaxed)
        }
        defer { probe.inside.subtract(1, ordering: .sequentiallyConsistent) }
        if returnZero { buffer.update(repeating: 7); return 0 }
        for i in 0..<buffer.count { buffer[i] = next; next += 1 }
        return buffer.count
    }
}

/// Polls `condition` until it holds or `timeout` passes.
private func eventually(timeout: Duration = .seconds(10),
                        _ condition: () -> Bool) -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        usleep(1_000)
    }
    return condition()
}

private func drain(_ ring: AudioBlockRing, blocks: Int) -> [[Float]] {
    var out: [[Float]] = []
    let deadline = ContinuousClock.now + .seconds(10)
    while out.count < blocks && ContinuousClock.now < deadline {
        if let b = ring.readableBlock() {
            out.append(Array(b))
            ring.releaseBlock()
        } else {
            usleep(100)
        }
    }
    return out
}

private func ramp(block k: Int, size: Int) -> [Float] {
    (k * size..<(k + 1) * size).map(Float.init)
}

@Suite(.timeLimit(.minutes(1)))
struct SimulationThreadTests {
    @Test func fillsRingAndParksWhenFull() {
        let ring = AudioBlockRing(capacity: 3, blockSize: 16)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        sim.start()
        #expect(sim.isRunning)
        #expect(eventually { ring.isFull && sim.parkCount >= 1 })
        #expect(sim.blocksProduced == 3)
        // Parked, not spinning: with nobody consuming, only the 20 ms
        // idle timeout wakes it (about 5 wake-ups in 100 ms).
        let p0 = sim.parkCount
        usleep(100_000)
        #expect(sim.parkCount - p0 <= 25)
        #expect(sim.blocksProduced == 3)

        let blocks = drain(ring, blocks: 50)
        #expect(blocks.count == 50)
        #expect(blocks.flatMap { $0 } == (0..<(50 * 16)).map(Float.init))
        // Exactly the drained blocks plus a refilled ring.
        #expect(eventually { ring.isFull })
        #expect(eventually { sim.blocksProduced == 53 })
        usleep(30_000)
        #expect(sim.blocksProduced == 53)
        sim.stop()
        #expect(!sim.isRunning)
        sim.stop()                                    // idempotent
    }

    @Test func idleTimeoutWakesTheParkedThread() {
        // Safety net: with the ring full and no consumer or command, the
        // thread still wakes periodically.
        let ring = AudioBlockRing(capacity: 1, blockSize: 4)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        sim.start()
        #expect(eventually { sim.parkCount >= 1 })
        let p0 = sim.parkCount
        #expect(eventually { sim.parkCount >= p0 + 3 })
        #expect(sim.blocksProduced == 1)
        sim.stop()
    }

    @Test func commandsRunInOrderBetweenBlocks() async {
        let ring = AudioBlockRing(capacity: 3, blockSize: 16)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        let threadName = Mutex<String?>(nil)
        for i in 0..<100 { sim.perform { $0.log.append(i) } }   // queued before start
        sim.start()
        for i in 100..<200 { sim.perform { $0.log.append(i) } }
        let log: [Int] = await withCheckedContinuation { cont in
            sim.perform { r in
                threadName.withLock { $0 = Thread.current.name }
                let snapshot = r.log
                cont.resume(returning: snapshot)
            }
        }
        #expect(log == Array(0..<200))
        #expect(threadName.withLock { $0 } == "mr-sim")
        sim.stop()
    }

    @Test func commandAffectsFollowingBlocks() async {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        sim.perform { $0.returnZero = true }
        sim.start()
        // returnZero → block played as silence at full length (C++ fill_n),
        // not the 7s the renderer left in the slot.
        let first = drain(ring, blocks: 1)
        #expect(first == [[Float](repeating: 0, count: 8)])
        // Flip back; every block rendered after the command is the ramp.
        let producedBefore: UInt64 = await withCheckedContinuation { cont in
            sim.perform { r in
                r.returnZero = false
                cont.resume(returning: sim.blocksProduced)
            }
        }
        let silentLeft = Int(producedBefore) - 1
        let rest = drain(ring, blocks: silentLeft + 3)
        #expect(rest.count == silentLeft + 3)
        #expect(rest.prefix(silentLeft).allSatisfy { $0 == [Float](repeating: 0, count: 8) })
        #expect(Array(rest.dropFirst(silentLeft)) == (0..<3).map { ramp(block: $0, size: 8) })
        sim.stop()
    }

    @Test func pendingCommandsRunBeforeStopReturns() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        let ran = Atomic<Int>(0)
        sim.start()
        for _ in 0..<10 { sim.perform { _ in ran.add(1, ordering: .relaxed) } }
        sim.stop()
        #expect(ran.load(ordering: .relaxed) == 10)
    }

    @Test func commandsPostedWhileStoppedRunOnNextStart() async {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        sim.start(); sim.stop()
        let ran = Atomic<Int>(0)
        sim.perform { _ in ran.add(1, ordering: .relaxed) }
        usleep(20_000)
        #expect(ran.load(ordering: .relaxed) == 0)
        sim.start()
        #expect(eventually { ran.load(ordering: .relaxed) == 1 })
        sim.stop()
    }

    @Test func restartAfterStopContinuesTheSameRenderer() async {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        sim.start()
        #expect(eventually { ring.isFull })
        sim.stop()
        #expect(sim.blocksProduced == 2)
        _ = drain(ring, blocks: 2)
        sim.start()
        #expect(sim.isRunning)
        // Read on the sim thread between blocks, where both are consistent:
        // the renderer kept its state across the restart.
        let (next, produced): (Float, UInt64) = await withCheckedContinuation { cont in
            sim.perform { cont.resume(returning: ($0.next, sim.blocksProduced)) }
        }
        #expect(produced >= 2)
        #expect(next == Float(produced * 8))
        let blocks = drain(ring, blocks: 2)
        #expect(blocks == [ramp(block: 2, size: 8), ramp(block: 3, size: 8)])
        sim.stop()
    }

    @Test func stopFromACommandClearsIsRunning() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer())
        sim.start()
        let after = Atomic<Int>(0)
        sim.perform { _ in sim.stop() }
        sim.perform { _ in after.add(1, ordering: .relaxed) }   // still drained
        #expect(eventually { !sim.isRunning })
        // start() from another thread waits for the old thread to exit,
        // so only one thread ever touches the renderer.
        sim.start()
        #expect(sim.isRunning)
        #expect(eventually { after.load(ordering: .relaxed) == 1 })
        sim.stop()
        #expect(!sim.isRunning)
    }

    @Test func deinitWithoutStopStopsTheThread() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        let probe = Probe()
        weak var weakSim: SimulationThread<FakeRenderer>?
        do {
            let sim = SimulationThread(ring: ring, renderer: FakeRenderer(probe: probe))
            weakSim = sim
            sim.start()
            #expect(eventually { ring.isFull })
        }
        #expect(weakSim == nil)
        // The thread exited and released the renderer.
        #expect(eventually { probe.deinits.load(ordering: .relaxed) == 1 })
        _ = drain(ring, blocks: 2)
        usleep(50_000)
        #expect(ring.isEmpty)                           // nobody refills it
    }

    @Test func concurrentStartStopNeverRunsTwoThreads() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 8)
        let probe = Probe()
        let sim = SimulationThread(ring: ring, renderer: FakeRenderer(probe: probe))
        let consumerDone = Atomic<Bool>(false)
        let consumer = Thread {
            while !consumerDone.load(ordering: .relaxed) {
                if ring.readableBlock() != nil { ring.releaseBlock() } else { sched_yield() }
            }
        }
        consumer.start()
        DispatchQueue.concurrentPerform(iterations: 4) { worker in
            for i in 0..<150 {
                if (i + worker) % 2 == 0 { sim.start() } else { sim.stop() }
                if i % 10 == 0 { sim.perform { _ in } }
            }
        }
        sim.start()
        #expect(sim.isRunning)
        #expect(eventually { sim.blocksProduced > 0 })
        sim.stop()
        #expect(!sim.isRunning)
        consumerDone.store(true, ordering: .relaxed)
        #expect(probe.overlaps.load(ordering: .relaxed) == 0)
        #expect(probe.inside.load(ordering: .relaxed) == 0)
    }

    @Test func postToMainRunsOnMainThread() async {
        let onMain: Bool = await withCheckedContinuation { cont in
            SimulationThread<FakeRenderer>.postToMain { cont.resume(returning: Thread.isMainThread) }
        }
        #expect(onMain)
        let onMainFree: Bool = await withCheckedContinuation { cont in
            postToMain { cont.resume(returning: Thread.isMainThread) }
        }
        #expect(onMainFree)
    }

    @Test func postToMainIsFifo() async {
        let order = Mutex<[Int]>([])
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            for i in 0..<50 { postToMain { order.withLock { $0.append(i) } } }
            postToMain { cont.resume() }
        }
        #expect(order.withLock { $0 } == Array(0..<50))
    }
}
