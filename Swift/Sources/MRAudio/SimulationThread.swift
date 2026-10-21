// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of the threading role of src/audio/SimulationWorker: a dedicated
// `mr-sim` thread (C++ QThread::HighPriority → QoS .userInteractive)
// that owns the block renderer (the Contest) and keeps the audio ring
// full. The Contest-specific slots of the C++ worker become closures
// posted with perform(_:), which run on the sim thread between blocks —
// the equivalent of a Qt::QueuedConnection slot invocation, FIFO order
// preserved. Settings snapshots are handed over the same way (the C++
// mutates Contest settings in queued slots and the Contest picks them up
// at the top of the next renderNextBlock).
//
// Pacing: the C++ polls every 4 ms and renders while the ring has room.
// Here the thread renders while the ring has room and otherwise parks
// on the ring's semaphore, which the audio render thread signals when it
// frees a slot (and perform/stop signal to deliver work promptly). A
// 20 ms timeout is a safety net only.
//
// The renderer is created/handed over once and from then on touched
// only by the sim thread, so the engine stays a plain single-threaded
// class (PORTING.md: no locks or actors inside the engine).
//
// Lifecycle: every start() creates a `Run` with its own stop flag and
// exit latch, so a stop() racing with a start() can only ever stop the
// run it observed. start() waits for a previous run that is still
// draining to exit first, so at most one thread touches the renderer.
// The thread captures only the shared `Core` (ring, renderer, command
// queue, counters) and its `Run` — never the SimulationThread object —
// so dropping the last reference runs deinit, which stops the thread.

import Dispatch
import Foundation
import Synchronization

/// The simulation engine as seen by the audio layer.
public protocol BlockRenderer: AnyObject, SendableMetatype {
    /// Renders the next block into `buffer` (`blockSize` samples) and
    /// returns how many samples were written. 0 means "nothing"; the
    /// block is then played as silence (C++ SimulationWorker::renderNextBlock).
    func renderNextBlock(into buffer: UnsafeMutableBufferPointer<Float>) -> Int
}

public final class SimulationThread<Renderer: BlockRenderer>: @unchecked Sendable {
    // @unchecked: the renderer lives in `Core` and is touched only by the
    // sim thread; everything else is immutable, Mutex- or Atomic-guarded.

    public typealias Command = @Sendable (Renderer) -> Void

    public var ring: AudioBlockRing { core.ring }
    private let core: Core
    private let state = Mutex<State>(State())

    /// What the sim thread needs; shared by the object and its thread.
    private final class Core: @unchecked Sendable {
        // @unchecked: `renderer` and `spare` are touched only by the sim
        // thread (one at a time, see start()); the rest is Mutex/Atomic.
        let ring: AudioBlockRing
        nonisolated(unsafe) let renderer: Renderer
        let commands = Mutex<[Command]>([])
        /// Sim thread only: the drained batch's buffer, reused so a drain
        /// does not allocate in steady state.
        nonisolated(unsafe) var spare: [Command] = []
        let produced = Atomic<UInt64>(0)
        let parks = Atomic<UInt64>(0)

        init(ring: AudioBlockRing, renderer: sending Renderer) {
            self.ring = ring
            self.renderer = renderer
        }
    }

    /// One start()…exit cycle of the sim thread.
    private final class Run: @unchecked Sendable {
        // @unchecked: `thread` is written once, under the state lock,
        // before the thread starts, and only read (identity) afterwards.
        // It is weak because the thread's closure retains this Run: a
        // strong reference would leak the Thread, the Run and the Core
        // (renderer included) once the thread exits.
        let stopRequested = Atomic<Bool>(false)
        let exitedFlag = Atomic<Bool>(false)
        /// Signalled once when the thread exits; every waiter re-signals
        /// it so it behaves as a latch for any number of waiters.
        let exited = DispatchSemaphore(value: 0)
        nonisolated(unsafe) weak var thread: Thread?

        var isCurrentThread: Bool { Thread.current === thread }

        func waitForExit() {
            exited.wait()
            exited.signal()
        }
    }

    private struct State: @unchecked Sendable {
        /// The running run (isRunning).
        var current: Run?
        /// A run asked to stop whose thread may not have exited yet.
        var stopping: Run?
    }

    /// Parked-wait timeout when the ring is full and no command arrives.
    public static var idleTimeoutNanoseconds: UInt64 { 20_000_000 }

    /// `renderer` must not be used by the caller afterwards: from now on
    /// only the sim thread touches it (reach it with perform(_:)).
    public init(ring: AudioBlockRing, renderer: sending Renderer) {
        core = Core(ring: ring, renderer: renderer)
    }

    /// Stops the thread (waiting for it, unless this is the sim thread
    /// itself, e.g. the last reference was dropped inside a command).
    deinit { stop() }

    /// Blocks pushed into the ring (C++ framesProduced).
    public var blocksProduced: UInt64 { core.produced.load(ordering: .relaxed) }

    /// Times the sim thread parked in waitForSpace() because the ring was
    /// full (each park lasts until a slot frees, a command/stop arrives
    /// or the idle timeout elapses). Test hook for "parks, not spins".
    var parkCount: UInt64 { core.parks.load(ordering: .relaxed) }

    public var isRunning: Bool { state.withLock { $0.current != nil } }

    /// Starts the sim thread; no-op if it is already running. If a
    /// previous run is still finishing (stop() was requested from the sim
    /// thread itself), waits for it to exit first. Called on that very
    /// sim thread while it is stopping, it does nothing (the thread is
    /// about to exit; call start() again from another thread).
    public func start() {
        while true {
            let pending: Run? = state.withLock { st in
                if st.current != nil { return nil }
                if let old = st.stopping {
                    if old.exitedFlag.load(ordering: .acquiring) {
                        st.stopping = nil
                    } else {
                        return old
                    }
                }
                let run = Run()
                let core = self.core
                let thread = Thread {
                    Self.run(core: core, run: run)
                    run.exitedFlag.store(true, ordering: .releasing)
                    run.exited.signal()
                }
                thread.name = "mr-sim"
                thread.qualityOfService = .userInteractive
                run.thread = thread
                st.current = run
                thread.start()
                return nil
            }
            guard let pending else { return }
            if pending.isCurrentThread { return }
            pending.waitForExit()
        }
    }

    /// Stops the thread and waits for it to exit. Commands already posted
    /// are executed first; commands posted after the thread's final drain
    /// stay queued and run on the next start(). Safe to call more than
    /// once and concurrently. Called from a command (i.e. on the sim
    /// thread) it requests the stop and returns without waiting;
    /// isRunning is false from then on.
    public func stop() {
        let run: Run? = state.withLock { st in
            if let r = st.current {
                st.current = nil
                st.stopping = r
                r.stopRequested.store(true, ordering: .sequentiallyConsistent)
                return r
            }
            return st.stopping
        }
        guard let run else { return }
        core.ring.wakeProducer()
        if run.isCurrentThread { return }
        run.waitForExit()
        state.withLock { st in
            if st.stopping === run { st.stopping = nil }
        }
    }

    /// Runs `command` on the sim thread before the next block (FIFO). If
    /// the thread is not running it runs when the thread starts.
    public func perform(_ command: @escaping Command) {
        core.commands.withLock { $0.append(command) }
        core.ring.wakeProducer()
    }

    /// Delivers a result to the main thread (sim → GUI). Same as the free
    /// function MRAudio.postToMain(_:); kept for existing callers.
    public static func postToMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        MRAudio.postToMain(body)
    }

    // MARK: - Sim thread

    private static func run(core: Core, run: Run) {
        pthread_setname_np("mr-sim")
        let ring = core.ring
        while !run.stopRequested.load(ordering: .sequentiallyConsistent) {
            drainCommands(core)
            if run.stopRequested.load(ordering: .sequentiallyConsistent) { break }
            let wrote = ring.write { slot in
                let n = core.renderer.renderNextBlock(into: slot)
                if n <= 0 {
                    slot.update(repeating: 0)
                    return slot.count
                }
                return n
            }
            if wrote {
                core.produced.add(1, ordering: .relaxed)
            } else {
                core.parks.add(1, ordering: .relaxed)
                ring.waitForSpace(timeoutNanoseconds: idleTimeoutNanoseconds)
            }
        }
        // The stop flag was set after any command posted before stop()
        // was enqueued, so this drain runs all of them.
        drainCommands(core)
    }

    /// Swaps the queue with the reusable spare buffer under the lock, so
    /// neither side copies or allocates once both have grown.
    private static func drainCommands(_ core: Core) {
        while true {
            var batch: [Command] = []
            swap(&batch, &core.spare)
            core.commands.withLock { swap(&$0, &batch) }
            if batch.isEmpty {
                swap(&batch, &core.spare)
                return
            }
            for command in batch { command(core.renderer) }
            batch.removeAll(keepingCapacity: true)
            swap(&batch, &core.spare)
        }
    }
}

/// Delivers a result to the main thread (sim → GUI). FIFO with respect to
/// other postToMain calls. Non-generic, so callers need not name a
/// SimulationThread specialization.
public func postToMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
}
