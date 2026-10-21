// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal Main.dfm RichEdit1 — read-only monospace pane showing the
// log header (blue underlined) and one row per logged QSO. Row format
// from Log.pas::LastQsoToScreen:
//
//   ' hh:nn:ss  %-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s'
//
// The last 3 characters (the error tag — "   "/"DUP"/"NIL"/"RST"/"NR ")
// are coloured red.
//
// Phase D leaves the pane empty (just the header). Phase E hooks
// appendQso() to Scoring::QsoLog updates.

#pragma once

#include <QTextEdit>

namespace mr::ui {

class LogView : public QTextEdit {
    Q_OBJECT
public:
    explicit LogView(QWidget* parent = nullptr);

    // Replace contents with the per-mode header and clear all rows.
    enum class HeaderStyle {
        WpxPrefix,     // " UTC ... Pref Chk"
        HstScore,      // " UTC ... Score Chk"
    };
    void setHeader(HeaderStyle style);

    // Append a pre-formatted row. Caller assembles the string via
    // Scoring::ScoreFormatter and passes the 3-char error tag
    // separately so the colored span lands on the right characters.
    void appendQsoRow(const QString& row, const QString& errorTag);
    // Pascal Contest.GetAudio re-check: delete the last line and write
    // it again (RichEdit1.Lines.Delete(Count-1); LastQsoToScreen).
    void replaceLastQsoRow(const QString& row);

    void clear();
};

}  // namespace mr::ui
