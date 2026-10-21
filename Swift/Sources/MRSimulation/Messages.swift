// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Port of Station.pas's TStationMessage enum and SendMsg dispatch
// (C++ src/simulation/Messages.{h,cpp}).
//
// Each enum value maps to a literal CW template containing the
// placeholders `<my>` (the sending station's callsign), `<his>` (the
// counterpart's callsign), and `<#>` (the cut-number-formatted RST+NR
// pair). Template substitution happens in Station.sendText at render
// time; the templates themselves are intentionally identical strings
// to the originals so the resulting CW envelopes match the Delphi
// reference for the same inputs.

import MRCore

/// Raw values equal the C++ `mr::sim::Message` values;
/// `Message.allCases.count` is the C++ `kMessageCount` (23).
public enum Message: Int, CaseIterable, Sendable {
    case none = 0, cq, nr, tu, myCall, hisCall, b4, qm, nilMsg, garbage,
         rNr, rNr2, deMyCall1, deMyCall2, deMyCallNr1, deMyCallNr2, nrQm,
         longCq, myCallNr2, qrl, qrl2, qsy, agn
}

/// Set of messages currently pending or recently sent by a station.
/// Mirrors the Pascal `TStationMessages = set of TStationMessage` and
/// the C++ `std::bitset<kMessageCount>`: bit i = Message raw value i, so
/// `rawValue` equals the C++ `to_ullong()`.
///
/// Conforms to `OptionSet` for the standard set algebra (`union`,
/// `formUnion`, `[]`, ...) on whole sets; single messages go through the
/// `Message`-taking `insert` / `contains` below, which keep the C++
/// semantics for `.none` (see `insert(_:)`).
public struct MessageSet: OptionSet, Hashable, Sendable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public init() { rawValue = 0 }

    public init(_ messages: [Message]) {
        rawValue = 0
        for m in messages { insert(m) }
    }

    /// C++ `messageSetOf(m)`: empty for `.none`.
    public static func of(_ m: Message) -> MessageSet {
        var s = MessageSet()
        if m != .none { s.insert(m) }
        return s
    }

    /// C++ `bitset::set(m)` — sets the bit unconditionally, also for
    /// `.none` (bit 0). The C++ DxStation timeout path relies on that:
    /// it hands the operator a set holding only `.none`, which is not
    /// empty (`count == 1`) yet matches no message, because
    /// `contains(.none)` is always false.
    public mutating func insert(_ m: Message) { rawValue |= 1 << UInt32(m.rawValue) }

    /// C++ `contains(s, m)`: always false for `.none`.
    public func contains(_ m: Message) -> Bool {
        m != .none && (rawValue >> UInt32(m.rawValue)) & 1 != 0
    }

    /// C++ `bitset::reset()`.
    public mutating func reset() { rawValue = 0 }

    /// C++ `bitset::count()` (counts bit 0 too).
    public var count: Int { rawValue.nonzeroBitCount }

    public var isEmpty: Bool { rawValue == 0 }

    public static func | (a: MessageSet, b: MessageSet) -> MessageSet {
        MessageSet(rawValue: a.rawValue | b.rawValue)
    }

    public static func |= (a: inout MessageSet, b: MessageSet) { a.rawValue |= b.rawValue }
}

// One slot per Message enum value, verbatim from Station.pas::SendMsg's
// case statement, including the peculiarities (extra space in msgQsy:
// `<his>  QSY QSY` — two spaces between `<his>` and QSY).
private let templates: [String] = [
    /* None        */ "",
    /* Cq          */ "CQ <my> TEST",
    /* Nr          */ "<#>",
    /* Tu          */ "TU",
    /* MyCall      */ "<my>",
    /* HisCall     */ "<his>",
    /* B4          */ "QSO B4",
    /* Qm          */ "?",
    /* Nil         */ "NIL",
    /* Garbage     */ "",
    /* R_Nr        */ "R <#>",
    /* R_Nr2       */ "R <#> <#>",
    /* DeMyCall1   */ "DE <my>",
    /* DeMyCall2   */ "DE <my> <my>",
    /* DeMyCallNr1 */ "DE <my> <#>",
    /* DeMyCallNr2 */ "DE <my> <my> <#>",
    /* NrQm        */ "NR?",
    /* LongCq      */ "CQ CQ TEST <my> <my> TEST",
    /* MyCallNr2   */ "<my> <my> <#>",
    /* Qrl         */ "QRL?",
    /* Qrl2        */ "QRL?   QRL?",
    /* Qsy         */ "<his>  QSY QSY",
    /* Agn         */ "AGN",
]

private let names: [String] = [
    "None", "Cq", "Nr", "Tu", "MyCall", "HisCall", "B4", "Qm", "Nil",
    "Garbage", "R_Nr", "R_Nr2", "DeMyCall1", "DeMyCall2", "DeMyCallNr1",
    "DeMyCallNr2", "NrQm", "LongCq", "MyCallNr2", "Qrl", "Qrl2", "Qsy",
    "Agn",
]

extension Message {
    /// The verbatim CW text template. Placeholders are `<my>`, `<his>`
    /// and `<#>`. Empty for `.none` and `.garbage` (the latter has no
    /// transmitted representation — it marks unintelligible reception).
    ///
    /// Pascal source: Station.pas::TStation.SendMsg case statement
    /// (C++ `templateFor`).
    public var template: String { templates[rawValue] }

    /// Short symbolic name (logging/debugging; not localized). C++
    /// `nameOf`.
    public var name: String { names[rawValue] }
}

// MARK: - Byte-string conveniences (all simulation text is ASCII)
//
// The replace / find / upper-case helpers themselves live in
// MRCore.ByteString, shared with the other modules.

extension Array where Element == UInt8 {
    var asString: String { String(decoding: self, as: UTF8.self) }
}

extension String {
    var bytes: [UInt8] { Array(utf8) }
}
