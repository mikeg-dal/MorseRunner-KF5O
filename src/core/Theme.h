// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Centralized style tokens. Two flavors:
//
//   LegacyLight  — pixel-faithful match to the original Delphi VCL look.
//                  Recommended for parity acceptance and for users who
//                  prefer the historic appearance.
//
//   SystemAdaptive — light / dark auto-derived from the macOS appearance.
//                    Background lightness is inverted in HSL space while
//                    accent chroma (clGreen, clAqua, clRed, clBlue, RIT
//                    orange) is preserved so the brand stays identifiable.
//
// Standard Qt widgets read the active TokenSet via `stylesheet()`. Custom
// painters (HistogramPanel, RitSlider, VolumeSlider, RecessedPanel) read
// `tokens()` directly to avoid stylesheet repaint thrash and to support
// non-CSS properties like inset bevel widths.

#pragma once

#include <QColor>
#include <QFont>
#include <QObject>
#include <QString>

namespace mr::core {

struct TokenSet {
    // Backgrounds
    QColor windowBg;
    QColor logBg;
    QColor histogramBg;
    QColor recessedBg;
    // Foregrounds
    QColor textPrimary;
    QColor textSecondary;
    QColor logoTopColor;
    QColor logoMidColor;
    QColor logoShadowColor;
    QColor copyrightColor;
    QColor logHeaderColor;
    QColor logErrorColor;
    QColor histogramBar;
    QColor ritIndicator;
    QColor clockText;
    QColor modeRedText;
    // Fonts
    QFont uiFont;
    QFont monoFont;
    QFont clockFont;
    QFont logoFont;
    QFont callEditFont;
    // Dimensions
    int recessedPanelBorderPx;
    int defaultPadPx;
};

class Theme : public QObject {
    Q_OBJECT
public:
    enum class Mode {
        LegacyLight,      // Pixel-faithful to Main.dfm
        SystemAdaptive,   // Follow macOS appearance, preserve accents
    };

    static Theme& instance();

    [[nodiscard]] const TokenSet& tokens() const { return current_; }
    [[nodiscard]] QString stylesheet() const;
    [[nodiscard]] Mode mode() const { return mode_; }

    void setMode(Mode mode);

signals:
    void themeChanged();

private:
    explicit Theme(QObject* parent = nullptr);
    void rebuild();

    Mode mode_ = Mode::SystemAdaptive;
    TokenSet current_;
};

}  // namespace mr::core
