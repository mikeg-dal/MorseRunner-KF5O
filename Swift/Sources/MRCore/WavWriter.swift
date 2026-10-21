// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal VCL/WavFile.pas (TAlWavFile.OpenWrite/WriteFrom) port, via the
// C++ src/core/WavWriter. RIFF/WAVE encoder for mono 16-bit PCM at the
// simulator's native 11025 Hz. open() writes a 44-byte header with zero
// sizes; both size fields are re-patched after every append (C++
// behaviour: the file stays playable even if the app is killed) and
// again on close().
//
// Sample conversion — deliberately Pascal's, not the C++ port's:
//  - Pascal writes `Round(x)` of the AGC output, which is already in
//    16-bit scale (AGC MaxOut 20000, so normally well inside ±32767).
//    Delphi Round is round-half-to-even → MRCore.delphiRound.
//  - The C++ port writes trunc(clamp(x, ±1) * 32767) of the ±1 stream
//    (x = agc / 32768), i.e. truncation plus a 32767/32768 gain error.
//    An audit flagged that as a parity bug; it is not reproduced.
//  - append(agcScale:) takes the AGC-scale samples directly.
//    append(normalized:) takes the ±1 Float stream the Contest hands to
//    the audio output and multiplies by 32768 — the exact inverse of
//    the Contest's kFloatPcmScale = 1/32768 (a power of two, so the
//    round trip is lossless) — then converts identically.
//  - Values outside the Int16 range are clamped (Pascal would wrap or
//    range-error; AGC output never gets there). NaN is written as 0.
//
// Size fields: RIFF sizes are 32-bit. Past 2^31 - 18 samples (about 54
// hours at 11025 Hz) the true data size no longer fits; the header then
// carries the largest representable even size while the samples keep
// being written unchanged (the usual convention for oversized WAVs).
//
// Errors: a failed open returns false. Later I/O failures (disk full,
// file removed under us) set `hasWriteError`, which stays set until the
// next open(); writing continues to be attempted, as the C++ does.
//
// Threading: not thread-safe; owned by the simulation thread. Uses
// buffered stdio and a reusable scratch buffer (no per-block allocation
// once the first block of a given size has been written).

import Darwin

public final class WavWriter {
    static let headerSize = 44
    /// Largest data size the header can state: 36 + size must fit the
    /// RIFF chunk's UInt32, rounded down to whole 16-bit samples.
    static let maxHeaderDataBytes: UInt32 = (UInt32.max - 36) & ~1

    public let sampleRate: UInt32

    private var file: UnsafeMutablePointer<FILE>?
    private var scratch: [UInt8] = []
    /// Samples appended since the last open() (not limited by the header).
    public private(set) var samplesWritten = 0
    /// True once any write, seek or flush since the last open() failed.
    public private(set) var hasWriteError = false

    /// - Precondition: `sampleRate` is positive and its byte rate
    ///   (2 × sampleRate) fits the header's UInt32 field.
    public init(sampleRate: Int = AudioK.sampleRate) {
        precondition(sampleRate > 0 && sampleRate <= Int(UInt32.max / 2),
                     "WavWriter: sampleRate \(sampleRate) out of range")
        self.sampleRate = UInt32(sampleRate)
    }

    deinit { close() }

    public var isOpen: Bool { file != nil }

    /// Opens (truncating) `path` and writes the placeholder header.
    /// Returns false if the file can't be created (e.g. missing directory).
    /// An already open file is closed (and finalized) first.
    @discardableResult
    public func open(path: String) -> Bool {
        close()
        guard let f = fopen(path, "wb") else { return false }
        return open(stream: f)
    }

    /// Takes ownership of an already open, writable, seekable stream and
    /// writes the placeholder header (tests use this with a funopen()
    /// stream to simulate I/O failures).
    func open(stream f: UnsafeMutablePointer<FILE>) -> Bool {
        close()
        file = f
        samplesWritten = 0
        hasWriteError = false
        let header = Self.header(sampleRate: sampleRate, dataBytes: 0)
        let ok = header.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, f) } == header.count
        if !ok {
            fclose(f)
            file = nil
        }
        return ok
    }

    /// Appends samples in the AGC's 16-bit scale (Pascal WriteFrom).
    public func append<C: Collection>(agcScale samples: C) where C.Element == Float {
        write(samples, gain: 1)
    }

    /// Appends samples of the ±1 Float output stream (agc / 32768).
    public func append<C: Collection>(normalized samples: C) where C.Element == Float {
        write(samples, gain: 32768)
    }

    /// Patches the header with the final sizes and closes. Idempotent.
    public func close() {
        guard let f = file else { return }
        patchHeader(f)
        if fclose(f) != 0 { hasWriteError = true }
        file = nil
    }

    /// Pascal `Round(x)` to Int16, clamped; NaN → 0.
    static func pcm16(_ x: Float) -> Int16 {
        guard !x.isNaN else { return 0 }
        let clamped = min(max(x, -32768), 32767)
        return Int16(delphiRound(clamped))
    }

    /// The canonical 44-byte PCM header (mono, 16-bit).
    static func header(sampleRate: UInt32, dataBytes: UInt32) -> [UInt8] {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        var h: [UInt8] = []
        h.reserveCapacity(headerSize)
        func tag(_ s: String) { h.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { h.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { h.append(contentsOf: $0) } }
        tag("RIFF"); u32(36 &+ dataBytes); tag("WAVE")  // wraps only past maxHeaderDataBytes
        tag("fmt "); u32(16); u16(1); u16(channels); u32(sampleRate); u32(byteRate)
        u16(blockAlign); u16(bitsPerSample)
        tag("data"); u32(dataBytes)
        return h
    }

    private func write<C: Collection>(_ samples: C, gain: Float) where C.Element == Float {
        guard let f = file else { return }
        let bytes = samples.count * 2
        if scratch.count < bytes { scratch = [UInt8](repeating: 0, count: bytes) }
        scratch.withUnsafeMutableBytes { raw in
            var i = 0
            for s in samples {
                let v = UInt16(bitPattern: Self.pcm16(s * gain)).littleEndian
                raw.storeBytes(of: v, toByteOffset: i, as: UInt16.self)
                i += 2
            }
            if bytes > 0 && fwrite(raw.baseAddress, 1, bytes, f) != bytes {
                hasWriteError = true
            }
        }
        samplesWritten += samples.count
        patchHeader(f)
        if fseeko(f, 0, SEEK_END) != 0 { hasWriteError = true }
    }

    /// Header data-size field for `samples` samples, clamped to
    /// `maxHeaderDataBytes`.
    static func headerDataBytes(samples: Int) -> UInt32 {
        let bytes = UInt64(samples) * 2
        return bytes > UInt64(maxHeaderDataBytes) ? maxHeaderDataBytes : UInt32(bytes)
    }

    private func patchHeader(_ f: UnsafeMutablePointer<FILE>) {
        let dataBytes = Self.headerDataBytes(samples: samplesWritten)
        func put(_ v: UInt32, at offset: off_t) {
            var le = v.littleEndian
            if fseeko(f, offset, SEEK_SET) != 0 || fwrite(&le, 4, 1, f) != 1 {
                hasWriteError = true
            }
        }
        put(36 + dataBytes, at: 4)
        put(dataBytes, at: 40)
        if fflush(f) != 0 || ferror(f) != 0 { hasWriteError = true }
    }
}
