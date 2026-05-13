// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "core/Theme.h"

#include "core/Constants.h"
#include "core/DelphiColor.h"

#include <QGuiApplication>
#include <QPalette>
#include <QStyleHints>

namespace mr::core {

namespace {

QFont makeFont(const QString& family, int pt, QFont::Weight weight = QFont::Normal,
               bool italic = false) {
    QFont f(family, pt, weight, italic);
    f.setStyleHint(QFont::SansSerif);
    return f;
}

// Legacy Light tokens — verbatim from Main.dfm (BGR literals decoded by
// DelphiColor::qcolorFromDelphi).
TokenSet legacyLightTokens() {
    using namespace mr::constants::Ui;
    TokenSet t;
    t.windowBg = QColor(0xF0, 0xF0, 0xF0);                          // clBtnFace approx
    t.logBg = qcolorFromDelphi(DfmColor::kLogBackgroundBgr);
    t.histogramBg = QColor(0xFF, 0xFF, 0xE1);                       // clInfoBk
    t.recessedBg = Qt::black;
    t.textPrimary = Qt::black;
    t.textSecondary = QColor(0x40, 0x40, 0x40);
    t.logoTopColor = Qt::green;                                     // clGreen
    t.logoMidColor = Qt::cyan;                                      // clAqua
    t.logoShadowColor = qcolorFromDelphi(DfmColor::kLogoShadowBgr);
    t.copyrightColor = QColor(0x30, 0x30, 0x30);
    t.logHeaderColor = Qt::blue;                                    // clBlue
    t.logErrorColor = Qt::red;                                      // clRed
    t.histogramBar = Qt::green;                                     // clGreen
    t.ritIndicator = qcolorFromDelphi(DfmColor::kRitIndicatorBgr);
    t.clockText = QColor(0xE0, 0xD7, 0xD7);                         // matches Panel2 face
    t.modeRedText = Qt::red;
    // Helvetica is the closest macOS analogue to MS Sans Serif at 11pt.
    t.uiFont = makeFont(QStringLiteral("Helvetica"), kDefaultFontPt);
    t.monoFont = makeFont(QStringLiteral("Menlo"), kLogFontPt);
    t.clockFont = makeFont(QStringLiteral("Helvetica"), kClockFontPt, QFont::Bold);
    t.logoFont = makeFont(QStringLiteral("Helvetica"), kLogoFontPt, QFont::Bold, /*italic=*/true);
    t.callEditFont = makeFont(QStringLiteral("Helvetica"), kCallEditFontPt, QFont::Bold);
    t.recessedPanelBorderPx = 1;
    t.defaultPadPx = 4;
    return t;
}

// Adaptive: starts from legacy, then darkens backgrounds when the host is
// in dark mode. Accent colors stay because they carry semantic meaning
// (red = error, blue = log header) and lose that meaning if remapped.
TokenSet adaptiveTokens() {
    TokenSet t = legacyLightTokens();
    const auto* hints = QGuiApplication::styleHints();
    if (hints != nullptr && hints->colorScheme() == Qt::ColorScheme::Dark) {
        t.windowBg = QColor(0x1E, 0x1E, 0x1E);
        t.logBg = QColor(0x12, 0x18, 0x1B);
        t.histogramBg = QColor(0x20, 0x20, 0x18);
        t.textPrimary = QColor(0xE6, 0xE6, 0xE6);
        t.textSecondary = QColor(0xB0, 0xB0, 0xB0);
        t.copyrightColor = QColor(0x90, 0x90, 0x90);
        t.clockText = QColor(0xFF, 0xC8, 0x66);
    }
    return t;
}

}  // namespace

Theme& Theme::instance() {
    static Theme t;
    return t;
}

Theme::Theme(QObject* parent) : QObject(parent) {
    rebuild();
    // Hook system appearance changes so dark mode flips propagate live.
    if (auto* hints = QGuiApplication::styleHints(); hints != nullptr) {
        connect(hints, &QStyleHints::colorSchemeChanged, this,
                [this](Qt::ColorScheme) {
                    if (mode_ == Mode::SystemAdaptive) {
                        rebuild();
                        emit themeChanged();
                    }
                });
    }
}

void Theme::setMode(Mode mode) {
    if (mode_ == mode) {
        return;
    }
    mode_ = mode;
    rebuild();
    emit themeChanged();
}

void Theme::rebuild() {
    current_ = (mode_ == Mode::LegacyLight) ? legacyLightTokens() : adaptiveTokens();
}

QString Theme::stylesheet() const {
    // The original VCL relied on native Windows theming for buttons,
    // edits, and group boxes. Qt's default macOS style already mirrors
    // that idiom, so we deliberately keep the stylesheet sparse and only
    // override what does NOT exist as a native control (recessed panel
    // bevels, log error coloring). Anything more elaborate would diverge
    // from a Mac user's expectations.
    return QStringLiteral(
        "QMainWindow { background: %1; }"
        "QStatusBar { background: %1; }"
    ).arg(current_.windowBg.name());
}

}  // namespace mr::core
