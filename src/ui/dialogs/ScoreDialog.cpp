// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/dialogs/ScoreDialog.h"

#include <QDesktopServices>
#include <QDialogButtonBox>
#include <QFont>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QUrl>
#include <QVBoxLayout>

namespace mr::ui {

namespace {

// Pascal Main.pas ViewScoreBoardMNUClick → OpenWebPage().
constexpr auto kScoreboardUrl =
    "http://www.dxatlas.com/MorseRunner/MrScore.asp";

}  // namespace

ScoreDialog::ScoreDialog(const QString& scoreString,
                         bool newHiScore,
                         QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("The contest is over"));
    setModal(true);

    auto* layout = new QVBoxLayout(this);

    if (newHiScore) {
        // Pascal stacks two TLabels: green text on aqua "shadow"
        // offset by 1 px. macOS native font rendering doesn't need
        // the shadow trick, so a single bold green label suffices.
        recordBanner_ = new QLabel(
            QStringLiteral("Congratulations on a new record!"), this);
        QFont bannerFont;
        bannerFont.setFamily(QStringLiteral("Arial"));
        bannerFont.setPointSize(16);
        bannerFont.setBold(true);
        recordBanner_->setFont(bannerFont);
        recordBanner_->setStyleSheet(QStringLiteral("color: #008000;"));
        recordBanner_->setAlignment(Qt::AlignCenter);
        layout->addWidget(recordBanner_);
    }

    auto* lbl = new QLabel(QStringLiteral("Your score string is:"), this);
    layout->addWidget(lbl);

    scoreEdit_ = new QLineEdit(scoreString, this);
    scoreEdit_->setReadOnly(true);
    scoreEdit_->setMinimumWidth(360);
    layout->addWidget(scoreEdit_);

    auto* buttons = new QDialogButtonBox(this);
    auto* scoreboardBtn = buttons->addButton(
        QStringLiteral("Scoreboard"), QDialogButtonBox::ActionRole);
    auto* okBtn = buttons->addButton(QDialogButtonBox::Ok);
    connect(scoreboardBtn, &QPushButton::clicked, this, []() {
        QDesktopServices::openUrl(QUrl(QString::fromLatin1(kScoreboardUrl)));
    });
    connect(okBtn, &QPushButton::clicked, this, &QDialog::accept);
    layout->addWidget(buttons);
}

}  // namespace mr::ui
