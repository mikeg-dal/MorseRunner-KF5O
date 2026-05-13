// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal VCL/WavFile.pas (TAlWavFile.OpenWrite/WriteFrom) port. RIFF/
// WAVE encoder for mono int16 PCM at the simulator's native 11025 Hz.
// On construction we write a placeholder header; close() seeks back
// and fixes the two size fields. Caller pushes float samples in ±1.0
// range via append(); we convert to int16 ±32767 inline.
//
// Threading: not thread-safe; intended for use from the sim thread
// only. The sim thread runs at HighPriority and writes one block of
// 512 samples per call (~46 ms cadence) — buffered file I/O at that
// rate is well within the per-block budget on modern SSDs.

#pragma once

#include <cstdint>
#include <fstream>
#include <span>
#include <string>

namespace mr::core {

class WavWriter {
public:
    WavWriter() = default;
    ~WavWriter();

    // Opens `path` for writing and emits a placeholder RIFF header.
    // Returns true on success; false if the path could not be opened
    // (e.g., destination directory missing — caller should mkpath).
    [[nodiscard]] bool open(const std::string& path);

    // Append one block of mono float samples. Out-of-range values are
    // clamped to ±1.0 before the int16 conversion.
    void append(std::span<const float> samples);

    // Flush, patch the header with final sample/byte counts, close.
    // Calling close() twice is a no-op. Destructor calls close().
    void close();

    [[nodiscard]] bool isOpen() const noexcept { return file_.is_open(); }

private:
    void writeHeaderPlaceholder();
    void patchHeader();

    std::ofstream file_;
    std::uint32_t samplesWritten_ = 0;
};

}  // namespace mr::core
