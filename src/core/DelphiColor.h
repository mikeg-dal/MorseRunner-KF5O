// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Bridge from Delphi `TColor` integer literals (as they appear inline in
// Main.dfm) to QColor. Delphi packs colors as BGR in the low 24 bits with
// the high byte zeroed for pure RGB colors. The high bit ($80000000) marks
// system colors (clBtnFace, clWindow, etc.); those are resolved at runtime
// against the active QPalette in Theme.cpp rather than here.

#pragma once

#include "core/Constants.h"

#include <QColor>
#include <QPalette>

#include <cstdint>

namespace mr::core {

// .dfm color constants that the port re-uses. Hex values shown in the
// trailing comments are the equivalent RGB after the BGR byte swap; they
// can be cross-checked against the original screenshots in
// docs/parity-checklist.md.
namespace DfmColor {
    inline constexpr std::uint32_t kLogBackgroundBgr   = 16711401u;  // RGB #E9FEFE — Shape1
    inline constexpr std::uint32_t kRitIndicatorBgr    = 12902431u;  // RGB #1FE0C4 — Shape2
    inline constexpr std::uint32_t kClockTextBgr       = 14151712u;  // RGB #20F0D7 — Panel2 font
    inline constexpr std::uint32_t kLogoShadowBgr      = 12369084u;  // RGB #BCBCBC — Label14 shadow
}  // namespace DfmColor

// Converts a non-system Delphi TColor literal to a QColor. Use this for any
// integer that came from a .dfm; system colors must be resolved via
// `paletteColorFor` instead.
[[nodiscard]] inline constexpr QColor qcolorFromDelphi(std::uint32_t bgr) noexcept {
    const auto b = static_cast<int>((bgr >> 16) & 0xFFu);
    const auto g = static_cast<int>((bgr >> 8) & 0xFFu);
    const auto r = static_cast<int>(bgr & 0xFFu);
    return QColor::fromRgb(r, g, b);
}

// Resolves a Delphi system color (high bit set) against the supplied
// palette. The mapping is intentionally narrow — only the system colors
// that actually appear in Main.dfm are supported, and unknown values fall
// back to the palette's window color so we never silently render black.
[[nodiscard]] inline QColor paletteColorFor(std::uint32_t delphiSysColor,
                                            const QPalette& palette) {
    // Delphi clBtnFace = $8000000F, clWindow = $80000005, etc. The lookup is
    // by the low byte; values are stable across Delphi versions.
    const auto code = static_cast<std::uint8_t>(delphiSysColor & 0xFFu);
    switch (code) {
        case 0x0F:  // clBtnFace
            return palette.color(QPalette::Button);
        case 0x05:  // clWindow
            return palette.color(QPalette::Base);
        case 0x08:  // clWindowText
            return palette.color(QPalette::WindowText);
        case 0x18:  // clInfoBk
            return palette.color(QPalette::ToolTipBase);
        default:
            return palette.color(QPalette::Window);
    }
}

}  // namespace mr::core
