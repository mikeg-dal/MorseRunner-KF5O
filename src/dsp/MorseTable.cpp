// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "dsp/MorseTable.h"

#include <array>
#include <cctype>
#include <string>
#include <string_view>
#include <unordered_map>

namespace mr::dsp {

namespace {

// 48 entries, verbatim from VCL/MorseTbl.pas. Each is {character or
// prosign mnemonic, pattern string}. Single-character entries are
// reachable through patternForChar; multi-character entries through
// patternForProsign.
struct Entry {
    std::string_view key;
    std::string_view pattern;
};

constexpr std::array<Entry, 48> kTable{{
    // Digits — note '0' is rendered as five dashes in CW.
    {"1", ".----"}, {"2", "..---"}, {"3", "...--"}, {"4", "....-"},
    {"5", "....."}, {"6", "-...."}, {"7", "--..."}, {"8", "---.."},
    {"9", "----."}, {"0", "-----"},
    // Letters.
    {"A", ".-"},    {"B", "-..."},  {"C", "-.-."},  {"D", "-.."},
    {"E", "."},     {"F", "..-."},  {"G", "--."},   {"H", "...."},
    {"I", ".."},    {"J", ".---"},  {"K", "-.-"},   {"L", ".-.."},
    {"M", "--"},    {"N", "-."},    {"O", "---"},   {"P", ".--."},
    {"Q", "--.-"},  {"R", ".-."},   {"S", "..."},   {"T", "-"},
    {"U", "..-"},   {"V", "...-"},  {"W", ".--"},   {"X", "-..-"},
    {"Y", "-.--"},  {"Z", "--.."},
    // Punctuation / contest characters.
    {"/", "-..-."}, {".", ".-.-.-"}, {",", "--..--"},
    {"?", "..--.."}, {"=", "-...-"},
    // Backslash is used in the original UI as a CQ shortcut; included
    // here so encode() doesn't drop it on encounter (it still maps to a
    // valid CW sign).
    {"\\", "...-."},
    // Multi-character prosigns. They are reached via patternForProsign
    // (the single-char lookup never matches these because their keys
    // are 2 chars wide).
    {"sk", "...-.-"},
    {"ar", ".-.-."},
    {"kn", "-.--."},
    {"cq", "-.-.--.-"},
    {"bk", "-...-.-"},
    {"dx", "-..-..-"},
}};

const std::unordered_map<char, std::string_view>& charMap() {
    static const auto m = [] {
        std::unordered_map<char, std::string_view> out;
        out.reserve(kTable.size());
        for (const auto& e : kTable) {
            if (e.key.size() == 1) {
                out.emplace(e.key[0], e.pattern);
            }
        }
        return out;
    }();
    return m;
}

const std::unordered_map<std::string, std::string_view>& prosignMap() {
    static const auto m = [] {
        std::unordered_map<std::string, std::string_view> out;
        for (const auto& e : kTable) {
            if (e.key.size() > 1) {
                std::string upper(e.key);
                for (auto& c : upper) {
                    c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
                }
                out.emplace(std::move(upper), e.pattern);
            }
        }
        return out;
    }();
    return m;
}

}  // namespace

std::string_view patternForChar(char c) noexcept {
    const char upper =
        static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    const auto& m = charMap();
    auto it = m.find(upper);
    return (it == m.end()) ? std::string_view{} : it->second;
}

std::string_view patternForProsign(std::string_view mnemonic) noexcept {
    std::string upper;
    upper.reserve(mnemonic.size());
    for (const char c : mnemonic) {
        upper.push_back(
            static_cast<char>(std::toupper(static_cast<unsigned char>(c))));
    }
    const auto& m = prosignMap();
    auto it = m.find(upper);
    return (it == m.end()) ? std::string_view{} : it->second;
}

std::string encodeMessage(std::string_view text) {
    // Mirrors VCL/MorseKey.pas::Encode: per-character lookup, separators
    // ' '/'_' become a single inter-letter space, the final character
    // (if any) is replaced with the '~' end-of-message marker so the
    // envelope generator knows to emit only a one-unit trailing gap
    // instead of the usual two-unit inter-character gap.
    std::string out;
    out.reserve(text.size() * 4);
    for (const char c : text) {
        if (c == ' ' || c == '_') {
            out.push_back(' ');
            continue;
        }
        const auto pat = patternForChar(c);
        if (pat.empty()) {
            continue;
        }
        out.append(pat);
        out.push_back(' ');  // inter-letter gap
    }
    if (!out.empty()) {
        out.back() = '~';
    }
    return out;
}

}  // namespace mr::dsp
