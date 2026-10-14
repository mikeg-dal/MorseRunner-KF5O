// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/panels/RightPanel.h"

#include "core/Constants.h"
#include "ui/widgets/VolumeSlider.h"

#include <QCheckBox>
#include <QComboBox>
#include <QGroupBox>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QRegularExpression>
#include <QRegularExpressionValidator>
#include <QSpinBox>
#include <QToolButton>

namespace mr::ui {

namespace {

// Pascal Main.dfm uses raw pixel coordinates inside Panel9 (alRight,
// 212×284). Centralized here to avoid magic numbers and to make a
// hypothetical future "scale-for-retina" pass easier.
namespace Geom {
    // Pascal Main.dfm Panel9 coordinates — preserved verbatim from
    // the original .dfm. The compact widget sizing depends on a
    // small font (set in applyCompactFont below) so Helvetica's
    // per-character width matches Windows MS Sans Serif at 11pt.
    constexpr int kPanelWidth = 212;
    constexpr int kPanelHeight = 284;

    // GroupBox1 "Station" — pixel-faithful Pascal layout.
    constexpr QRect kStationGroup{9, 6, 194, 159};
    constexpr QRect kCallLabel{12, 20, 25, 13};
    constexpr QRect kCallEdit{36, 16, 89, 21};
    constexpr QRect kCwSpeedLabel{12, 48, 55, 13};
    constexpr QRect kWpmLabel{156, 48, 32, 13};
    constexpr QRect kWpmSpin{88, 44, 65, 22};
    constexpr QRect kQskCheckBox{140, 18, 50, 17};
    constexpr QRect kCwPitchLabel{12, 76, 50, 13};
    constexpr QRect kPitchCombo{88, 72, 65, 21};
    constexpr QRect kRxBandwidthLabel{12, 104, 72, 13};
    constexpr QRect kBandwidthCombo{88, 100, 65, 21};
    constexpr QRect kMonLevelLabel{12, 134, 58, 13};
    constexpr QRect kVolumeSlider{89, 132, 60, 20};

    // GroupBox3 "Band Conditions"
    constexpr QRect kBandGroup{9, 170, 194, 81};
    constexpr QRect kQrnCheckBox{12, 18, 50, 17};
    constexpr QRect kQrmCheckBox{12, 38, 50, 17};
    constexpr QRect kQsbCheckBox{12, 58, 50, 17};
    constexpr QRect kFlutterCheckBox{76, 18, 58, 17};
    constexpr QRect kLidsCheckBox{76, 40, 50, 17};
    constexpr QRect kActivityLabel{144, 16, 40, 13};
    constexpr QRect kActivitySpin{144, 32, 40, 22};

    // Panel10 (alBottom, height 31)
    constexpr int kRunRowY = 253;
    constexpr int kRunRowHeight = 31;
    constexpr QRect kForLabel{103, 9, 16, 13};
    constexpr QRect kDurationSpin{122, 7, 50, 22};
    constexpr QRect kMinLabel{175, 9, 28, 13};
    constexpr QRect kRunButton{13, 5, 84, 24};
}  // namespace Geom

// Pascal MS Sans Serif 11pt is roughly equivalent in pixel width to
// macOS Helvetica 10pt. Apply this to every child in the right panel
// so labels and combo entries fit the .dfm widget widths.
void applyCompactFont(QWidget* root) {
    QFont compact = root->font();
    compact.setPointSize(10);
    for (auto* w : root->findChildren<QWidget*>()) {
        QFont f = w->font();
        f.setPointSize(10);
        w->setFont(f);
    }
}

// Maximum 12-char uppercase callsign with letters, digits, and `/?`.
// Pascal Main.dfm Edit4 has CharCase=ecUpperCase, MaxLength=12; we
// match those via a Qt validator.
constexpr int kCallsignMaxLen = 12;

}  // namespace

RightPanel::RightPanel(QMenu* runPopupMenu, QWidget* parent) : QWidget(parent) {
    using mr::constants::Ui::kRightPanelHeight;
    using mr::constants::Ui::kRightPanelWidth;
    setFixedSize(kRightPanelWidth, kRightPanelHeight);

    // Pascal: GroupBox1 + GroupBox3 + Panel10 sit directly on Panel9.
    // We build each into the same RightPanel, no extra container.
    buildStationGroup(this);
    buildBandConditionsGroup(this);
    buildRunRow(this, runPopupMenu);

    // macOS Helvetica needs a smaller point size to match Windows MS
    // Sans Serif widths at the .dfm pixel coordinates.
    applyCompactFont(this);
}

void RightPanel::buildStationGroup(QWidget* host) {
    using namespace mr::constants::Ui;

    auto* group = new QGroupBox(QStringLiteral("Station"), host);
    group->setGeometry(Geom::kStationGroup);

    auto addLabel = [&](const QString& text, const QRect& r) {
        auto* lbl = new QLabel(text, group);
        lbl->setGeometry(r);
    };

    addLabel(QStringLiteral("Call"), Geom::kCallLabel);
    callEdit_ = new QLineEdit(group);
    callEdit_->setGeometry(Geom::kCallEdit);
    callEdit_->setText(QStringLiteral("VE3NEA"));
    callEdit_->setMaxLength(kCallsignMaxLen);
    callEdit_->setAccessibleName(QStringLiteral("My callsign"));
    callEdit_->setAccessibleDescription(QStringLiteral(
        "Your amateur radio callsign, sent in CW transmissions"));
    // CharCase=ecUpperCase equivalent: validator with explicit upper.
    callEdit_->setValidator(new QRegularExpressionValidator(
        QRegularExpression(QStringLiteral("[A-Za-z0-9/?]{0,%1}").arg(kCallsignMaxLen)),
        callEdit_));
    // Bridge to uppercase as the user types; matches Delphi's ecUpperCase.
    connect(callEdit_, &QLineEdit::textChanged, callEdit_, [this](const QString& t) {
        const QString u = t.toUpper();
        if (u != t) {
            const int pos = callEdit_->cursorPosition();
            QSignalBlocker b(callEdit_);
            callEdit_->setText(u);
            callEdit_->setCursorPosition(pos);
        }
    });

    addLabel(QStringLiteral("CW Speed"), Geom::kCwSpeedLabel);
    addLabel(QStringLiteral("WPM"), Geom::kWpmLabel);
    wpmSpin_ = new QSpinBox(group);
    wpmSpin_->setGeometry(Geom::kWpmSpin);
    wpmSpin_->setRange(kWpmMin, kWpmMax);
    wpmSpin_->setValue(30);
    wpmSpin_->setAccessibleName(QStringLiteral("CW speed"));
    wpmSpin_->setAccessibleDescription(QStringLiteral(
        "Player CW sending speed in words per minute"));

    qskCheckBox_ = new QCheckBox(QStringLiteral("QSK"), group);
    qskCheckBox_->setGeometry(Geom::kQskCheckBox);
    qskCheckBox_->setChecked(true);
    qskCheckBox_->setAccessibleName(QStringLiteral("QSK full break-in"));
    qskCheckBox_->setAccessibleDescription(QStringLiteral(
        "When on, the receiver opens between sent dots and dashes "
        "so DX stations can break in"));

    addLabel(QStringLiteral("CW Pitch"), Geom::kCwPitchLabel);
    pitchCombo_ = new QComboBox(group);
    pitchCombo_->setGeometry(Geom::kPitchCombo);
    pitchCombo_->setAccessibleName(QStringLiteral("CW pitch in hertz"));
    for (int hz = kPitchMinHz; hz <= kPitchMaxHz; hz += kPitchStepHz) {
        pitchCombo_->addItem(QStringLiteral("%1 Hz").arg(hz), hz);
    }
    pitchCombo_->setCurrentIndex(
        (600 - kPitchMinHz) / kPitchStepHz);  // default 600 Hz

    addLabel(QStringLiteral("RX Bandwidth"), Geom::kRxBandwidthLabel);
    bandwidthCombo_ = new QComboBox(group);
    bandwidthCombo_->setGeometry(Geom::kBandwidthCombo);
    bandwidthCombo_->setAccessibleName(QStringLiteral("Receiver bandwidth"));
    bandwidthCombo_->setAccessibleDescription(QStringLiteral(
        "Width of the audio filter applied to the simulated receiver "
        "output, in hertz"));
    for (int hz = kBandwidthMinHz; hz <= kBandwidthMaxHz; hz += kBandwidthStepHz) {
        bandwidthCombo_->addItem(QStringLiteral("%1 Hz").arg(hz), hz);
    }
    bandwidthCombo_->setCurrentIndex(
        (500 - kBandwidthMinHz) / kBandwidthStepHz);  // default 500 Hz

    addLabel(QStringLiteral("Mon. Level"), Geom::kMonLevelLabel);
    auto* slider = new VolumeSlider(group);
    slider->setGeometry(Geom::kVolumeSlider);
    slider->setAccessibleName(QStringLiteral("Self-monitor volume"));
    slider->setAccessibleDescription(QStringLiteral(
        "Loudness of your own CW sidetone during transmission, "
        "from silent to loud"));
    volumeSliderHost_ = slider;
}

void RightPanel::buildBandConditionsGroup(QWidget* host) {
    using namespace mr::constants::Ui;

    auto* group = new QGroupBox(QStringLiteral("Band Conditions"), host);
    group->setGeometry(Geom::kBandGroup);

    auto addCheck = [&](const QString& text, const QRect& r,
                        const QString& a11yDesc) {
        auto* cb = new QCheckBox(text, group);
        cb->setGeometry(r);
        cb->setChecked(true);
        cb->setAccessibleDescription(a11yDesc);
        return cb;
    };

    qrnCheckBox_     = addCheck(QStringLiteral("QRN"), Geom::kQrnCheckBox,
        QStringLiteral("Atmospheric noise — random clicks and crashes "
                        "on the simulated band"));
    qrmCheckBox_     = addCheck(QStringLiteral("QRM"), Geom::kQrmCheckBox,
        QStringLiteral("Man-made interference — competing CW stations "
                        "on adjacent frequencies"));
    qsbCheckBox_     = addCheck(QStringLiteral("QSB"), Geom::kQsbCheckBox,
        QStringLiteral("Fading — Rayleigh-distributed signal strength "
                        "variation typical of HF propagation"));
    flutterCheckBox_ = addCheck(QStringLiteral("Flutter"), Geom::kFlutterCheckBox,
        QStringLiteral("Polar-path flutter — fast amplitude modulation "
                        "on some DX signals"));
    lidsCheckBox_    = addCheck(QStringLiteral("LIDs"), Geom::kLidsCheckBox,
        QStringLiteral("Poor operators — occasional NR errors, wrong "
                        "RSTs, and call mishearings in the DX pile"));

    auto* activityLabel = new QLabel(QStringLiteral("Activity"), group);
    activityLabel->setGeometry(Geom::kActivityLabel);

    activitySpin_ = new QSpinBox(group);
    activitySpin_->setGeometry(Geom::kActivitySpin);
    activitySpin_->setRange(kActivityMin, kActivityMax);
    activitySpin_->setValue(3);
    activitySpin_->setAccessibleName(QStringLiteral("Band activity level"));
    // Pascal spawns RndPoisson(Activity / 2) callers per CQ, so low
    // settings often leave a CQ unanswered — say so where it's set.
    const QString activityHelp = QStringLiteral(
        "Average callers per CQ ≈ Activity ÷ 2. At 1, most CQs go "
        "unanswered; use 3–5 for a busy pile-up.");
    activitySpin_->setToolTip(activityHelp);
    activityLabel->setToolTip(activityHelp);
    activitySpin_->setAccessibleDescription(activityHelp);
}

void RightPanel::buildRunRow(QWidget* host, QMenu* runPopupMenu) {
    using namespace mr::constants::Ui;

    auto* row = new QWidget(host);
    row->setGeometry(0, Geom::kRunRowY, Geom::kPanelWidth, Geom::kRunRowHeight);

    // ToolBar1 with single dropdown button. Pascal: Style=tbsDropDown,
    // DropdownMenu=PopupMenu1, ImageIndex=0. Qt equivalent is
    // QToolButton::MenuButtonPopup with setMenu().
    runButton_ = new QToolButton(row);
    runButton_->setGeometry(Geom::kRunButton);
    runButton_->setText(QStringLiteral("   Run   "));
    // Pascal ToolButton1Click: the button body toggles — Pile-Up when
    // stopped, Stop while a run is active — and the dropdown arrow
    // opens the menu for choosing a different mode. MenuButtonPopup
    // gives us the split visual; MainWindow wires the body's clicked
    // signal because only it knows whether a run is active.
    runButton_->setPopupMode(QToolButton::MenuButtonPopup);
    if (runPopupMenu != nullptr) {
        runButton_->setMenu(runPopupMenu);
    }

    auto* forLabel = new QLabel(QStringLiteral("for"), row);
    forLabel->setGeometry(Geom::kForLabel);

    durationSpin_ = new QSpinBox(row);
    durationSpin_->setGeometry(Geom::kDurationSpin);
    durationSpin_->setRange(kDurationMin, kDurationMax);
    durationSpin_->setValue(30);

    auto* minLabel = new QLabel(QStringLiteral("min."), row);
    minLabel->setGeometry(Geom::kMinLabel);
}

}  // namespace mr::ui
