// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AVFAudio
import Foundation
@testable import MRAudio
import Testing

@Suite struct RingPlaybackSourceTests {
    private func makeRing(blocks: Int, blockSize: Int = 512, capacity: Int = 8) -> AudioBlockRing {
        let ring = AudioBlockRing(capacity: capacity, blockSize: blockSize)
        var v: Float = 0
        for _ in 0..<blocks {
            ring.write { slot in
                for i in 0..<slot.count { slot[i] = v; v += 1 }
                return slot.count
            }
        }
        return ring
    }

    private func render(_ src: RingPlaybackSource, _ n: Int) -> ([Float], Bool) {
        var out = [Float](repeating: -99, count: n)
        let silent = out.withUnsafeMutableBufferPointer { src.render(into: $0) }
        return (out, silent)
    }

    @Test func unalignedRequestsStitchBlocksSeamlessly() {
        let src = RingPlaybackSource(ring: makeRing(blocks: 4))
        var all: [Float] = []
        for n in [100, 471, 512, 7, 300, 658] {        // sums to 2048 = 4 blocks
            let (out, silent) = render(src, n)
            #expect(!silent)
            all += out
        }
        #expect(all == (0..<2048).map(Float.init))
        #expect(src.underrunCount == 0)
        #expect(src.blocksEmitted == 4)
        #expect(src.ring.isEmpty)
    }

    @Test func partiallyConsumedBlockStaysInRing() {
        let src = RingPlaybackSource(ring: makeRing(blocks: 1))
        _ = render(src, 200)
        #expect(src.ring.count == 1)                   // still held
        #expect(src.blocksEmitted == 0)
        let (out, _) = render(src, 312)
        #expect(out.first == 200 && out.last == 511)
        #expect(src.ring.isEmpty)
        #expect(src.blocksEmitted == 1)
    }

    @Test func underrunPadsWithSilenceAndCounts() {
        let src = RingPlaybackSource(ring: makeRing(blocks: 1))
        let (out, silent) = render(src, 600)
        #expect(!silent)
        #expect(Array(out[0..<512]) == (0..<512).map(Float.init))
        #expect(out[512...].allSatisfy { $0 == 0 })
        #expect(src.underrunCount == 1)

        let (out2, silent2) = render(src, 256)
        #expect(silent2)
        #expect(out2.allSatisfy { $0 == 0 })
        #expect(src.underrunCount == 2)
    }

    @Test func resumesAfterUnderrun() {
        let ring = AudioBlockRing(capacity: 2, blockSize: 4)
        let src = RingPlaybackSource(ring: ring)
        _ = render(src, 3)
        ring.write { s in s.update(repeating: 5); return 4 }
        let (out, silent) = render(src, 4)
        #expect(!silent && out == [5, 5, 5, 5])
        #expect(src.underrunCount == 1)
    }

    @Test func renderCallbackFillsAudioBufferList() {
        let ring = makeRing(blocks: 2)
        let src = RingPlaybackSource(ring: ring)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 11025,
                                   channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        var isSilence: ObjCBool = true
        AudioOutput.render(source: src, frameCount: 700,
                           bufferList: buffer.mutableAudioBufferList, isSilence: &isSilence)
        #expect(!isSilence.boolValue)
        let ch = buffer.floatChannelData![0]
        #expect(ch[0] == 0 && ch[699] == 699)
        #expect(src.blocksEmitted == 1)

        AudioOutput.render(source: src, frameCount: 1024,
                           bufferList: buffer.mutableAudioBufferList, isSilence: &isSilence)
        #expect(!isSilence.boolValue)
        #expect(ch[0] == 700 && ch[323] == 1023 && ch[324] == 0)
        #expect(src.underrunCount == 1)
    }

    @Test func emptyOutputBufferConsumesNothing() {
        let src = RingPlaybackSource(ring: makeRing(blocks: 1))
        #expect(!src.render(into: UnsafeMutableBufferPointer(start: nil, count: 0)))
        var one: Float = -1
        let empty = withUnsafeMutablePointer(to: &one) {
            src.render(into: UnsafeMutableBufferPointer(start: $0, count: 0))
        }
        #expect(!empty)
        #expect(one == -1)
        #expect(src.ring.count == 1)
        #expect(src.underrunCount == 0 && src.blocksEmitted == 0)
    }

    @Test func zeroLengthBlocksAreSkipped() {
        let ring = AudioBlockRing(capacity: 4, blockSize: 4)
        ring.write { _ in 0 }
        ring.write { s in s.update(repeating: 3); return 4 }
        ring.write { _ in 0 }
        let src = RingPlaybackSource(ring: ring)
        let (out, silent) = render(src, 4)
        #expect(!silent && out == [3, 3, 3, 3])
        #expect(src.blocksEmitted == 2)                 // the empty one + the full one
        #expect(ring.count == 1)                        // trailing empty block not reached yet
        let (out2, silent2) = render(src, 2)
        #expect(silent2 && out2 == [0, 0])              // drains it, then underruns
        #expect(src.blocksEmitted == 3)
        #expect(src.underrunCount == 1)
    }

    // MARK: AudioOutput.render over raw AudioBufferLists

    private func withBufferList(_ capacities: [Int],
                                _ body: (UnsafeMutablePointer<AudioBufferList>, [UnsafeMutablePointer<Float>]) -> Void) {
        let abl = AudioBufferList.allocate(maximumBuffers: max(capacities.count, 1))
        defer { free(abl.unsafeMutablePointer) }
        abl.count = capacities.count
        var storage: [UnsafeMutablePointer<Float>] = []
        for (i, cap) in capacities.enumerated() {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(cap, 1))
            p.initialize(repeating: -99, count: max(cap, 1))
            storage.append(p)
            abl[i] = AudioBuffer(mNumberChannels: 1,
                                 mDataByteSize: UInt32(cap * MemoryLayout<Float>.size),
                                 mData: UnsafeMutableRawPointer(p))
        }
        defer { storage.forEach { $0.deallocate() } }
        body(abl.unsafeMutablePointer, storage)
    }

    @Test func renderCopiesChannelZeroIntoEveryFurtherBuffer() {
        let src = RingPlaybackSource(ring: makeRing(blocks: 1, blockSize: 8))
        withBufferList([6, 6, 4]) { list, bufs in
            var isSilence: ObjCBool = true
            AudioOutput.render(source: src, frameCount: 6, bufferList: list, isSilence: &isSilence)
            #expect(!isSilence.boolValue)
            #expect(Array(UnsafeBufferPointer(start: bufs[0], count: 6)) == [0, 1, 2, 3, 4, 5])
            #expect(Array(UnsafeBufferPointer(start: bufs[1], count: 6)) == [0, 1, 2, 3, 4, 5])
            // Third buffer holds only 4 frames: truncated, nothing past it touched.
            #expect(Array(UnsafeBufferPointer(start: bufs[2], count: 4)) == [0, 1, 2, 3])
        }
    }

    @Test func renderNeverWritesPastTheBufferCapacity() {
        let src = RingPlaybackSource(ring: makeRing(blocks: 1, blockSize: 8))
        withBufferList([5]) { list, bufs in
            var isSilence: ObjCBool = true
            AudioOutput.render(source: src, frameCount: 100, bufferList: list, isSilence: &isSilence)
            #expect(!isSilence.boolValue)
            #expect(Array(UnsafeBufferPointer(start: bufs[0], count: 5)) == [0, 1, 2, 3, 4])
        }
        // Only the 5 frames that fit were consumed.
        #expect(src.ring.count == 1 && src.blocksEmitted == 0 && src.underrunCount == 0)
        var rest = [Float](repeating: 0, count: 3)
        rest.withUnsafeMutableBufferPointer { _ = src.render(into: $0) }
        #expect(rest == [5, 6, 7])
    }

    @Test func renderWithAnEmptyBufferListIsANoOp() {
        let src = RingPlaybackSource(ring: makeRing(blocks: 1, blockSize: 8))
        withBufferList([]) { list, _ in
            var isSilence: ObjCBool = false
            AudioOutput.render(source: src, frameCount: 8, bufferList: list, isSilence: &isSilence)
            #expect(!isSilence.boolValue)               // untouched
        }
        #expect(src.ring.count == 1 && src.underrunCount == 0)
    }

    @Test func renderReportsSilenceWhenTheRingIsEmpty() {
        let src = RingPlaybackSource(ring: AudioBlockRing(capacity: 2, blockSize: 8))
        withBufferList([4]) { list, bufs in
            var isSilence: ObjCBool = false
            AudioOutput.render(source: src, frameCount: 4, bufferList: list, isSilence: &isSilence)
            #expect(isSilence.boolValue)
            #expect(Array(UnsafeBufferPointer(start: bufs[0], count: 4)) == [0, 0, 0, 0])
        }
        #expect(src.underrunCount == 1)
    }
}
