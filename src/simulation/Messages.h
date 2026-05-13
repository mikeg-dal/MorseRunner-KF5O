// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Station.pas's TStationMessage enum and SendMsg dispatch.
//
// Each enum value maps to a literal CW template containing the
// placeholders `<my>` (the sending station's callsign), `<his>` (the
// counterpart's callsign), and `<#>` (the cut-number-formatted RST+NR
// pair). Template substitution happens in Station::sendText at render
// time; the templates themselves are intentionally identical strings
// to the originals so the resulting CW envelopes match the Delphi
// reference for the same inputs.

#pragma once

#include <bitset>
#include <cstddef>
#include <string_view>

namespace mr::sim {

enum class Message : std::size_t {
    None = 0,
    Cq,
    Nr,
    Tu,
    MyCall,
    HisCall,
    B4,
    Qm,
    Nil,
    Garbage,
    R_Nr,
    R_Nr2,
    DeMyCall1,
    DeMyCall2,
    DeMyCallNr1,
    DeMyCallNr2,
    NrQm,
    LongCq,
    MyCallNr2,
    Qrl,
    Qrl2,
    Qsy,
    Agn,
    Count,
};

// Number of distinct Message values (used to size the bitset and the
// template table).
inline constexpr std::size_t kMessageCount = static_cast<std::size_t>(Message::Count);

// Set of messages currently pending or recently sent by a station.
// Mirrors the Pascal `TStationMessages = set of TStationMessage` —
// callers ask "did this station's last send include msgCq?".
using MessageSet = std::bitset<kMessageCount>;

[[nodiscard]] inline MessageSet messageSetOf(Message m) {
    MessageSet s;
    if (m != Message::None && m != Message::Count) {
        s.set(static_cast<std::size_t>(m));
    }
    return s;
}

[[nodiscard]] inline bool contains(const MessageSet& s, Message m) {
    return (m != Message::None && m != Message::Count)
           && s.test(static_cast<std::size_t>(m));
}

// Returns the verbatim CW text template for `m`. Placeholders are
// `<my>`, `<his>`, and `<#>`. The empty string is returned for
// Message::None and Message::Garbage (the latter has no transmitted
// representation — it marks unintelligible reception).
//
// Pascal source: Station.pas::TStation.SendMsg case statement.
[[nodiscard]] std::string_view templateFor(Message m) noexcept;

// Returns a short symbolic name for `m` — useful for logging and
// debugging. Not localized.
[[nodiscard]] std::string_view nameOf(Message m) noexcept;

}  // namespace mr::sim
