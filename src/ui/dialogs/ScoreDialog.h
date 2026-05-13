// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal ScoreDlg.pas port. Modal dialog shown when a WPX run ends.
// Displays the submission score string (read-only QLineEdit), an
// optional "Congratulations on a new record!" banner when the user
// beat their previous HiScore, plus two buttons: "Scoreboard"
// (opens the DX Atlas leaderboard URL in the system browser) and
// "OK" (closes the dialog).

#pragma once

#include <QDialog>
#include <QString>

class QLineEdit;
class QLabel;

namespace mr::ui {

class ScoreDialog : public QDialog {
    Q_OBJECT
public:
    explicit ScoreDialog(const QString& scoreString,
                         bool newHiScore,
                         QWidget* parent = nullptr);

private:
    QLineEdit* scoreEdit_ = nullptr;
    QLabel* recordBanner_ = nullptr;
};

}  // namespace mr::ui
