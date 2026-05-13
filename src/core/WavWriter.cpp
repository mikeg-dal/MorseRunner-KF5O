// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "core/WavWriter.h"

#include "core/Constants.h"

#include <algorithm>
#include <array>
#include <cstring>

namespace mr::core {

namespace {

// RIFF/WAVE little-endian byte writers. We don't use a struct with
// __attribute__((packed)) because we want zero ambiguity about field
// order across compilers — the WAV format predates standard endianness
// rules and benefits from explicit serialization.
inline void writeU32(std::ostream& os, std::uint32_t v) {
    const std::array<char, 4> bytes = {
        static_cast<char>(v & 0xFF),
        static_cast<char>((v >> 8) & 0xFF),
        static_cast<char>((v >> 16) & 0xFF),
        static_cast<char>((v >> 24) & 0xFF),
    };
    os.write(bytes.data(), 4);
}

inline void writeU16(std::ostream& os, std::uint16_t v) {
    const std::array<char, 2> bytes = {
        static_cast<char>(v & 0xFF),
        static_cast<char>((v >> 8) & 0xFF),
    };
    os.write(bytes.data(), 2);
}

// PCM full-scale for int16 conversion. Matches Pascal output which is
// also int16-clamped.
constexpr float kInt16Max = 32767.0F;

}  // namespace

WavWriter::~WavWriter() {
    close();
}

bool WavWriter::open(const std::string& path) {
    close();
    file_.open(path, std::ios::binary | std::ios::trunc);
    if (!file_) {
        return false;
    }
    samplesWritten_ = 0;
    writeHeaderPlaceholder();
    return static_cast<bool>(file_);
}

void WavWriter::writeHeaderPlaceholder() {
    using namespace mr::constants::Audio;
    // Standard 44-byte RIFF/WAVE/PCM header. We write zeros for the
    // two size fields (RIFF chunk size at offset 4, data chunk size at
    // offset 40) and patch them in close() once the total sample count
    // is known.
    constexpr std::uint16_t kChannels      = 1;
    constexpr std::uint16_t kBitsPerSample = 16;
    const std::uint32_t sampleRate         = kSampleRate;
    const std::uint16_t blockAlign         = kChannels * (kBitsPerSample / 8);
    const std::uint32_t byteRate           = sampleRate * blockAlign;

    file_.write("RIFF", 4);
    writeU32(file_, 0);          // placeholder: RIFF chunk size
    file_.write("WAVE", 4);
    file_.write("fmt ", 4);
    writeU32(file_, 16);         // fmt chunk size
    writeU16(file_, 1);          // PCM format
    writeU16(file_, kChannels);
    writeU32(file_, sampleRate);
    writeU32(file_, byteRate);
    writeU16(file_, blockAlign);
    writeU16(file_, kBitsPerSample);
    file_.write("data", 4);
    writeU32(file_, 0);          // placeholder: data chunk size
}

void WavWriter::append(std::span<const float> samples) {
    if (!file_) {
        return;
    }
    // Convert + clamp inline. A buffered ofstream's write() is well
    // under 1 µs per 512-sample block on modern SSDs; doing the
    // conversion in a loop here avoids a temporary allocation.
    for (const float s : samples) {
        const float clamped = std::clamp(s, -1.0F, 1.0F);
        const auto v = static_cast<std::int16_t>(clamped * kInt16Max);
        writeU16(file_, static_cast<std::uint16_t>(v));
    }
    samplesWritten_ += static_cast<std::uint32_t>(samples.size());
    // Patch the RIFF chunk-size and data chunk-size headers after
    // every append, then seek back to end. This costs two 4-byte
    // writes per ~46 ms audio block — negligible vs the typical
    // 1-KB-per-block payload — and guarantees the file is always
    // structurally valid for playback even if the app is SIGKILLed
    // without close() running. Without this patch, a crash leaves a
    // RIFF file with zero-byte header sizes that CoreAudio's
    // AudioFileOpen rejects with 'dta?'.
    patchHeader();
    file_.seekp(0, std::ios::end);
}

void WavWriter::patchHeader() {
    if (!file_) {
        return;
    }
    // data chunk size = sample count * bytes-per-sample (2 for int16
    // mono). RIFF chunk size = 36 + data chunk size (the 36 covers
    // everything between 'WAVE' and 'data' inclusive).
    constexpr std::uint32_t kBytesPerSample = 2;
    const std::uint32_t dataBytes = samplesWritten_ * kBytesPerSample;
    const std::uint32_t riffSize  = 36 + dataBytes;

    file_.seekp(4);
    writeU32(file_, riffSize);
    file_.seekp(40);
    writeU32(file_, dataBytes);
}

void WavWriter::close() {
    if (!file_.is_open()) {
        return;
    }
    patchHeader();
    file_.flush();
    file_.close();
}

}  // namespace mr::core
