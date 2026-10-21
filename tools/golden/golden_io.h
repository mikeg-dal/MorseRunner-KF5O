// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Tiny writers for reference data: raw little-endian float32 arrays and
// a minimal JSON builder. Floats are printed with 9 significant digits,
// which round-trips every float exactly.

#pragma once

#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <type_traits>
#include <vector>

namespace golden {

inline std::filesystem::path g_outDir;

inline std::filesystem::path out(const std::string& rel) {
    auto p = g_outDir / rel;
    std::filesystem::create_directories(p.parent_path());
    return p;
}

inline void writeFloats(const std::string& rel, const std::vector<float>& v) {
    std::ofstream f(out(rel), std::ios::binary);
    f.write(reinterpret_cast<const char*>(v.data()),
            static_cast<std::streamsize>(v.size() * sizeof(float)));
}

inline void writeText(const std::string& rel, const std::string& text) {
    std::ofstream f(out(rel));
    f << text;
}

inline std::string num(float x) {
    char b[32];
    std::snprintf(b, sizeof b, "%.9g", static_cast<double>(x));
    return b;
}
inline std::string num(double x) {
    char b[40];
    std::snprintf(b, sizeof b, "%.17g", x);
    return b;
}
inline std::string num(int x) { return std::to_string(x); }
inline std::string num(unsigned x) { return std::to_string(x); }
inline std::string num(long long x) { return std::to_string(x); }
inline std::string num(std::size_t x) { return std::to_string(x); }

inline std::string str(const std::string& s) {
    std::string o = "\"";
    for (char c : s) {
        if (c == '"' || c == '\\') { o += '\\'; }
        o += c;
    }
    return o + "\"";
}

template <typename T>
std::string arr(const std::vector<T>& v) {
    std::string o = "[";
    for (std::size_t i = 0; i < v.size(); ++i) {
        if (i) o += ",";
        if constexpr (std::is_same_v<T, std::string>) o += str(v[i]);
        else o += num(v[i]);
    }
    return o + "]";
}

// Usage: main(argc, argv) { golden::init(argc, argv); ... }
inline void init(int argc, char** argv) {
    g_outDir = (argc > 1) ? argv[1] : ".";
}

}  // namespace golden
