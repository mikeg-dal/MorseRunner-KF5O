// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
@testable import MRCore
import Testing

private func tempPath() -> String {
    NSTemporaryDirectory() + "mr-wav-\(UUID().uuidString).wav"
}

private func readBytes(_ path: String) throws -> [UInt8] {
    try [UInt8](Data(contentsOf: URL(fileURLWithPath: path)))
}

private func pcmSamples(_ d: [UInt8]) -> [Int16] {
    stride(from: WavWriter.headerSize, to: d.count, by: 2).map {
        Int16(bitPattern: UInt16(d[$0]) | UInt16(d[$0 + 1]) << 8)
    }
}

private func u32(_ d: [UInt8], at i: Int) -> UInt32 {
    UInt32(d[i]) | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2]) << 16 | UInt32(d[i + 3]) << 24
}

// funopen() callbacks: a sink that accepts everything, and one whose
// every write fails (as on a full disk).
private func acceptWrite(_: UnsafeMutableRawPointer?, _: UnsafePointer<CChar>?, n: Int32) -> Int32 { n }
private func failWrite(_: UnsafeMutableRawPointer?, _: UnsafePointer<CChar>?, _: Int32) -> Int32 {
    errno = ENOSPC
    return -1
}
private func seekAnywhere(_: UnsafeMutableRawPointer?, offset: fpos_t, _: Int32) -> fpos_t { offset }

private func makeStream(failing: Bool) -> UnsafeMutablePointer<FILE>? {
    failing ? funopen(nil, nil, failWrite, seekAnywhere, nil)
            : funopen(nil, nil, acceptWrite, seekAnywhere, nil)
}

@Suite struct WavWriterTests {
    @Test func headerLayout() {
        let h = WavWriter.header(sampleRate: 11025, dataBytes: 6)
        let expected: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, 42, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,   // RIFF 36+6 WAVE
            0x66, 0x6D, 0x74, 0x20, 16, 0, 0, 0, 1, 0, 1, 0,              // fmt  16 PCM mono
            0x11, 0x2B, 0, 0, 0x22, 0x56, 0, 0, 2, 0, 16, 0,              // 11025, 22050, 2, 16
            0x64, 0x61, 0x74, 0x61, 6, 0, 0, 0,                           // data 6
        ]
        #expect(h == expected)
        #expect(h.count == WavWriter.headerSize)
    }

    @Test func pascalRoundingAndClamp() {
        #expect(WavWriter.pcm16(0.5) == 0)           // half to even
        #expect(WavWriter.pcm16(1.5) == 2)
        #expect(WavWriter.pcm16(2.5) == 2)
        #expect(WavWriter.pcm16(-2.5) == -2)
        #expect(WavWriter.pcm16(1234.6) == 1235)     // C++ would truncate
        #expect(WavWriter.pcm16(-1234.6) == -1235)
        #expect(WavWriter.pcm16(40000) == 32767)
        #expect(WavWriter.pcm16(-40000) == -32768)
        #expect(WavWriter.pcm16(.infinity) == 32767)
        #expect(WavWriter.pcm16(-.infinity) == -32768)
        #expect(WavWriter.pcm16(.nan) == 0)
    }

    @Test func writesSamplesAndPatchesHeader() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let w = WavWriter()
        #expect(w.open(path: path))
        w.append(agcScale: [Float(1.5), -2.5, 32767.4])
        // Normalized stream: x/32768 round-trips exactly.
        w.append(normalized: [Float(1000.5) / 32768, -1.0, 2.0])
        // Header is valid mid-recording (crash safety).
        let mid = try readBytes(path)
        #expect(mid.count == 44 + 12)
        #expect(mid[40] == 12)
        w.close()
        w.close()                                     // idempotent
        let d = try readBytes(path)
        #expect(Array(d[0..<44]) == WavWriter.header(sampleRate: 11025, dataBytes: 12))
        #expect(pcmSamples(d) == [2, -2, 32767, 1000, -32768, 32767])
        #expect(w.samplesWritten == 6)
        #expect(!w.isOpen)
        #expect(!w.hasWriteError)
    }

    @Test func nanIsWrittenAsZero() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let w = WavWriter()
        #expect(w.open(path: path))
        w.append(agcScale: [Float.nan, 7, -.nan])
        w.append(normalized: [Float.nan])
        w.close()
        #expect(pcmSamples(try readBytes(path)) == [0, 7, 0, 0])
    }

    @Test func acceptsAnyFloatCollection() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let w = WavWriter()
        #expect(w.open(path: path))
        w.append(agcScale: (0..<3).lazy.map { Float($0) * 10 })          // lazy collection
        let source: [Float] = [-1, -2, -3, -4]
        w.append(agcScale: source[1...2])                                // ArraySlice
        source.withUnsafeBufferPointer { w.append(agcScale: $0) }        // buffer pointer
        w.append(normalized: repeatElement(Float(0.5), count: 2))        // Repeated
        w.append(agcScale: [Float]())                                    // empty block
        w.close()
        let d = try readBytes(path)
        #expect(pcmSamples(d) == [0, 10, 20, -2, -3, -1, -2, -3, -4, 16384, 16384])
        #expect(u32(d, at: 40) == 22)
        #expect(w.samplesWritten == 11)
    }

    @Test func reopenWhileOpenFinalizesTheFirstFile() throws {
        let first = tempPath()
        let second = tempPath()
        defer {
            try? FileManager.default.removeItem(atPath: first)
            try? FileManager.default.removeItem(atPath: second)
        }
        let w = WavWriter()
        #expect(w.open(path: first))
        w.append(agcScale: [Float(1), 2, 3])
        #expect(w.open(path: second))
        #expect(w.samplesWritten == 0)
        w.append(agcScale: [Float(4)])
        w.close()
        let a = try readBytes(first)
        #expect(Array(a[0..<44]) == WavWriter.header(sampleRate: 11025, dataBytes: 6))
        #expect(pcmSamples(a) == [1, 2, 3])
        let b = try readBytes(second)
        #expect(Array(b[0..<44]) == WavWriter.header(sampleRate: 11025, dataBytes: 2))
        #expect(pcmSamples(b) == [4])
    }

    @Test(arguments: [8000, 22050, 44100, 48000])
    func nonDefaultSampleRateHeader(_ rate: Int) throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let w = WavWriter(sampleRate: rate)
        #expect(w.sampleRate == UInt32(rate))
        #expect(w.open(path: path))
        w.append(agcScale: [Float(9)])
        w.close()
        let d = try readBytes(path)
        #expect(Array(d[0..<44]) == WavWriter.header(sampleRate: UInt32(rate), dataBytes: 2))
        #expect(u32(d, at: 24) == UInt32(rate))        // sample rate
        #expect(u32(d, at: 28) == UInt32(rate * 2))    // byte rate
    }

    @Test func openFailsForMissingDirectory() {
        let w = WavWriter()
        #expect(!w.open(path: "/nonexistent-dir-mr/x.wav"))
        #expect(!w.isOpen)
        w.append(agcScale: [Float(1)])                // no-op, no crash
        #expect(w.samplesWritten == 0)
    }

    @Test func writeErrorIsReported() throws {
        let w = WavWriter()
        let f = try #require(makeStream(failing: true))
        // The header is only buffered, so open succeeds; the failure
        // surfaces when the first block is flushed.
        #expect(w.open(stream: f))
        #expect(!w.hasWriteError)
        w.append(agcScale: [Float(1), 2])
        #expect(w.hasWriteError)
        w.close()
        #expect(w.hasWriteError)                      // sticky until the next open
    }

    @Test func writeErrorClearsOnReopen() throws {
        let w = WavWriter()
        #expect(w.open(stream: try #require(makeStream(failing: true))))
        w.append(agcScale: [Float(1)])
        #expect(w.hasWriteError)
        #expect(w.open(stream: try #require(makeStream(failing: false))))
        #expect(!w.hasWriteError)
        w.append(agcScale: [Float(1)])
        w.close()
        #expect(!w.hasWriteError)
    }

    @Test func headerSizeFieldIsClampedPastFourGigabytes() {
        let maxSamples = Int(WavWriter.maxHeaderDataBytes / 2)
        #expect(WavWriter.maxHeaderDataBytes == 0xFFFF_FFDA)
        #expect(WavWriter.headerDataBytes(samples: 0) == 0)
        #expect(WavWriter.headerDataBytes(samples: 5) == 10)
        #expect(WavWriter.headerDataBytes(samples: maxSamples) == WavWriter.maxHeaderDataBytes)
        #expect(WavWriter.headerDataBytes(samples: maxSamples + 1) == WavWriter.maxHeaderDataBytes)
        #expect(WavWriter.headerDataBytes(samples: Int(UInt32.max) * 4) == WavWriter.maxHeaderDataBytes)
        // 36 + the clamped size still fits the RIFF field.
        #expect(UInt64(WavWriter.maxHeaderDataBytes) + 36 <= UInt64(UInt32.max))
    }

    @Test func zeroSampleRateTraps() async {
        await #expect(processExitsWith: .failure) { _ = WavWriter(sampleRate: 0) }
    }

    @Test func negativeSampleRateTraps() async {
        await #expect(processExitsWith: .failure) { _ = WavWriter(sampleRate: -11025) }
    }
}
