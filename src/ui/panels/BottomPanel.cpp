// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/panels/BottomPanel.h"

#include "core/Constants.h"
#include "ui/widgets/HistogramPanel.h"
#include "ui/widgets/RitSlider.h"

#include <QFont>
#include <QFrame>
#include <QLabel>
#include <QLineEdit>
#include <QPalette>
#include <QPushButton>
#include <QRegularExpression>
#include <QRegularExpressionValidator>

namespace mr::ui {

namespace {

// Pixel-faithful Pascal coordinates. The panel is 700 wide and 119
// high; everything inside is positioned absolutely relative to it.
namespace Geom {
    // Pascal Main.dfm Panel1 height = 119. Native macOS widgets are
    // notably larger than Windows equivalents at the same point size,
    // so this port scales the bottom panel up substantially. The log
    // area above shrinks accordingly but the user-facing readability
    // wins. Documented "platform delta" in docs/parity-checklist.md.
    constexpr int kPanelHeight = 160;

    // Entry fields ────────────────────────────────────────────────────
    constexpr QRect kCallLabel{16, 14, 30, 18};
    constexpr QRect kCallEdit{12, 32, 165, 32};
    constexpr QRect kRstLabel{186, 14, 30, 18};
    constexpr QRect kRstEdit{182, 32, 52, 32};
    constexpr QRect kNrLabel{244, 14, 24, 18};
    constexpr QRect kNrEdit{240, 32, 52, 32};

    // F1..F8 buttons in two rows. 30 px tall, room for descenders +
    // native button chrome.
    constexpr int kFKeyWidth = 67;
    constexpr int kFKeyHeight = 30;
    constexpr int kFKeyRow1Y = 72;
    constexpr int kFKeyRow2Y = 108;
    constexpr int kFKeyColStartX = 12;
    constexpr int kFKeyColStride = 70;

    // Vertical separator between the entry strip and the status strip.
    constexpr QRect kSeparator{300, 6, 2, kPanelHeight - 12};

    // Status panels ──────────────────────────────────────────────────
    constexpr QRect kModePanel{316, 10, 120, 26};
    constexpr QRect kRatePanel{446, 10, 110, 26};
    constexpr QRect kClockPanel{566, 10, 124, 38};

    constexpr QRect kHistogramHost{316, 42, 240, 72};
    constexpr QRect kRitSliderHost{316, 120, 240, 12};

    // Score frame: 105 px tall to fit 1 header row + 3 data rows
    // comfortably at native macOS label spacing.
    constexpr QRect kHiScoreFrame{566, 52, 124, 100};
}  // namespace Geom

// Identifying labels for each F-key. Pascal Tags 1..8 map to the
// Sim::Message enum but the order/text below mirrors the .dfm exactly.
struct FKeyDef {
    const char* labelText;
};
constexpr FKeyDef kFKeyDefs[8] = {
    {"F1  CQ"},
    {"F2  <#>"},
    {"F3  TU"},
    {"F4  <my>"},
    {"F5  <his>"},
    {"F6  B4"},
    {"F7  ?"},
    {"F8  NIL"},
};

// Main.dfm fonts are Font.Height in pixels; a Qt point on macOS is one
// logical pixel, so the sizes carry over 1:1. MS Sans Serif becomes
// Helvetica (platform delta); Arial is available on macOS.
QFont dfmFont(const char* family, int px, bool bold = false) {
    QFont f(QString::fromLatin1(family));
    f.setPointSize(px);
    f.setBold(bold);
    return f;
}

}  // namespace

BottomPanel::BottomPanel(QWidget* parent) : QWidget(parent) {
    using namespace mr::constants::Ui;

    setFixedHeight(Geom::kPanelHeight);

    // Pascal: Panel1 BevelOuter=bvLowered, BevelInner=bvRaised. Qt
    // QFrame with Box/Raised gives the equivalent inset+outset look.
    auto* frame = new QFrame(this);
    frame->setFrameStyle(QFrame::Box | QFrame::Raised);
    frame->setLineWidth(1);
    frame->setMidLineWidth(1);
    frame->setGeometry(0, 0, kMainWindowWidth, Geom::kPanelHeight);

    buildEntryFields(frame);
    buildFunctionKeys(frame);

    // Vertical bevel between entry strip and the status strip.
    auto* sep = new QFrame(frame);
    sep->setGeometry(Geom::kSeparator);
    sep->setFrameShape(QFrame::VLine);
    sep->setFrameShadow(QFrame::Sunken);

    buildModePanel(frame);
    buildRatePanel(frame);
    buildClockPanel(frame);
    buildHistogramPanel(frame);
    buildRitSliderPanel(frame);
    buildScoreTable(frame);

    // MainForm font: MS Sans Serif, Height -11. Widgets that set their
    // own font above (entry fields, clock, mode, HST score) keep it.
    setFont(dfmFont("Helvetica", 11));
}

void BottomPanel::buildEntryFields(QWidget* host) {
    // Pascal Edit1 (Call): Bold 16pt, MaxLen 12, allowed
    // [A-Za-z0-9/?]. Pascal Edit2 (RST): 16pt, MaxLen 3, [0-9].
    // Pascal Edit3 (Nr): 16pt, MaxLen 4, [0-9].
    auto* callLbl = new QLabel(QStringLiteral("Call"), host);
    callLbl->setGeometry(Geom::kCallLabel);
    auto* rstLbl  = new QLabel(QStringLiteral("RST"),  host);
    rstLbl->setGeometry(Geom::kRstLabel);
    auto* nrLbl   = new QLabel(QStringLiteral("Nr."),  host);
    nrLbl->setGeometry(Geom::kNrLabel);

    // Edit1/2/3: MS Sans Serif, Height -16, bold.
    const QFont boldBig = dfmFont("Helvetica", 16, true);

    callEdit_ = new QLineEdit(host);
    callEdit_->setGeometry(Geom::kCallEdit);
    callEdit_->setFont(boldBig);
    callEdit_->setMaxLength(12);
    callEdit_->setValidator(new QRegularExpressionValidator(
        QRegularExpression(QStringLiteral("[A-Za-z0-9/?]{0,12}")), callEdit_));
    callEdit_->setAccessibleName(QStringLiteral("Heard callsign"));
    callEdit_->setAccessibleDescription(QStringLiteral(
        "Type the callsign you hear from the DX station; "
        "F5 sends it back as your guess"));
    // Pascal Edit1.CharCase = ecUpperCase. IsMyCall is case-sensitive,
    // so a lowercase typed call ("kf5o" vs "KF5O") fails IsMyCall with
    // a cost-8 penalty and the DX silently drops to NeedPrevEnd. Force
    // uppercase the way Pascal did. textChanged is reused for the
    // heardCallsignChanged emit further up, so we mutate the edit and
    // re-fire — the QSignalBlocker prevents recursion.
    connect(callEdit_, &QLineEdit::textChanged, callEdit_,
            [this](const QString& t) {
                const QString u = t.toUpper();
                if (u == t) {
                    return;
                }
                const int pos = callEdit_->cursorPosition();
                QSignalBlocker b(callEdit_);
                callEdit_->setText(u);
                callEdit_->setCursorPosition(pos);
                emit callEdit_->textChanged(u);
            });

    rstEdit_ = new QLineEdit(host);
    rstEdit_->setGeometry(Geom::kRstEdit);
    rstEdit_->setFont(boldBig);
    rstEdit_->setMaxLength(3);
    rstEdit_->setValidator(new QRegularExpressionValidator(
        QRegularExpression(QStringLiteral("[0-9]{0,3}")), rstEdit_));
    rstEdit_->setAccessibleName(QStringLiteral("Received signal report"));
    rstEdit_->setAccessibleDescription(QStringLiteral(
        "Three-digit RST report copied from the DX station, "
        "typically 599 if you heard them cleanly"));

    nrEdit_ = new QLineEdit(host);
    nrEdit_->setGeometry(Geom::kNrEdit);
    nrEdit_->setFont(boldBig);
    nrEdit_->setMaxLength(4);
    nrEdit_->setValidator(new QRegularExpressionValidator(
        QRegularExpression(QStringLiteral("[0-9]{0,4}")), nrEdit_));
    nrEdit_->setAccessibleName(QStringLiteral("Received contest number"));
    nrEdit_->setAccessibleDescription(QStringLiteral(
        "The serial number the DX station sent — required to "
        "score the QSO"));
}

void BottomPanel::buildFunctionKeys(QWidget* host) {
    // Pascal Main.dfm SpeedButton4..11. Layout: 4 buttons per row,
    // two rows. Each fires Tag-based dispatch in the .pas; the Tag
    // value maps to a Sim::Message enum. Phase E wires the buttons
    // to MainWindow::sendMessageRequested.
    // Plain-English equivalents for VoiceOver. The button labels show
    // both the F-key shortcut and the Pascal message name ("F1 CQ",
    // etc.); these descriptions explain what each F-key actually does
    // in CW-contesting terms for a screen reader user.
    static constexpr const char* kFKeyA11y[8] = {
        "Send CQ — calls for any DX station to reply",
        "Send your contest number — the player's RST and serial",
        "Send TU — thank you, marks the end of a successful QSO",
        "Send your own callsign",
        "Send the heard callsign back to the DX as confirmation",
        "Send QSO B4 — tells the caller you've already worked them",
        "Send a question mark — requests a repeat",
        "Send NIL — tells the caller you didn't copy anything",
    };
    for (int i = 0; i < 8; ++i) {
        const int row = i / 4;
        const int col = i % 4;
        auto* btn = new QPushButton(
            QString::fromLatin1(kFKeyDefs[i].labelText), host);
        btn->setGeometry(
            Geom::kFKeyColStartX + col * Geom::kFKeyColStride,
            (row == 0) ? Geom::kFKeyRow1Y : Geom::kFKeyRow2Y,
            Geom::kFKeyWidth, Geom::kFKeyHeight);
        btn->setAccessibleDescription(
            QString::fromLatin1(kFKeyA11y[i]));
        fKeyButtons_[i] = btn;
    }
}

void BottomPanel::buildModePanel(QWidget* host) {
    // Pascal Panel4: BevelOuter=bvLowered, MS Sans Serif Height -11,
    // bold. Caption and colour (green, or red for competitions) are set
    // by Run(). Empty in Stop mode.
    modeLabel_ = new QLabel(host);
    modeLabel_->setGeometry(Geom::kModePanel);
    modeLabel_->setFrameStyle(QFrame::StyledPanel | QFrame::Sunken);
    modeLabel_->setAlignment(Qt::AlignCenter);
    modeLabel_->setFont(dfmFont("Helvetica", 11, true));
    QPalette p = modeLabel_->palette();
    p.setColor(QPalette::WindowText, Qt::red);
    modeLabel_->setPalette(p);
    modeLabel_->setText(QStringLiteral(""));  // Stop mode at startup
    modeLabel_->setAccessibleName(QStringLiteral("Run mode"));
}

void BottomPanel::buildRatePanel(QWidget* host) {
    // Pascal Panel7: bvLowered. ShowRate writes "%d  qso/hr." here.
    rateLabel_ = new QLabel(host);
    rateLabel_->setGeometry(Geom::kRatePanel);
    rateLabel_->setFrameStyle(QFrame::StyledPanel | QFrame::Sunken);
    rateLabel_->setAlignment(Qt::AlignCenter);
    rateLabel_->setText(QStringLiteral("0  qso/hr."));
    rateLabel_->setAccessibleName(QStringLiteral("QSO rate"));
    rateLabel_->setAccessibleDescription(QStringLiteral(
        "Average QSOs per hour for the current session"));
}

void BottomPanel::buildClockPanel(QWidget* host) {
    // Pascal Panel2: BevelOuter=bvLowered, black background, Arial
    // Height -24 in colour 14151712.
    clockLabel_ = new QLabel(host);
    clockLabel_->setGeometry(Geom::kClockPanel);
    clockLabel_->setFrameStyle(QFrame::StyledPanel | QFrame::Sunken);
    clockLabel_->setAlignment(Qt::AlignCenter);
    clockLabel_->setAutoFillBackground(true);
    QPalette p = clockLabel_->palette();
    p.setColor(QPalette::Window, Qt::black);
    // TColor 14151712 = $00D7F020, stored $00BBGGRR → RGB #20F0D7 (cyan).
    p.setColor(QPalette::WindowText, QColor(0x20, 0xF0, 0xD7));
    clockLabel_->setPalette(p);
    clockLabel_->setFont(dfmFont("Arial", 24));
    clockLabel_->setText(QStringLiteral("00:00:00"));
    clockLabel_->setAccessibleName(QStringLiteral("Session clock"));
    clockLabel_->setAccessibleDescription(QStringLiteral(
        "Elapsed simulated contest time, hours minutes seconds"));
}

void BottomPanel::buildHistogramPanel(QWidget* host) {
    // Pascal Panel3 + PaintBox1. HistogramPanel is the custom paint
    // (D.G4) that mirrors Log.pas::PaintHisto.
    auto* hostFrame = new QFrame(host);
    hostFrame->setGeometry(Geom::kHistogramHost);
    hostFrame->setFrameStyle(QFrame::StyledPanel | QFrame::Sunken);
    histogramPanel_ = new HistogramPanel(hostFrame);
    histogramPanel_->setGeometry(1, 1,
                                 Geom::kHistogramHost.width() - 2,
                                 Geom::kHistogramHost.height() - 2);
    histogramPanel_->setAccessibleName(QStringLiteral("QSO histogram"));
    histogramPanel_->setAccessibleDescription(QStringLiteral(
        "Bar chart of QSOs logged per 5-minute window across the "
        "contest, up to 240 minutes"));
}

void BottomPanel::buildRitSliderPanel(QWidget* host) {
    // Pascal Panel8 + Shape2 — RitSlider draws the recessed groove
    // and orange indicator (D.G4).
    ritSlider_ = new RitSlider(host);
    ritSlider_->setGeometry(Geom::kRitSliderHost);
    ritSlider_->setAccessibleName(QStringLiteral("RIT — receiver tuning"));
    ritSlider_->setAccessibleDescription(QStringLiteral(
        "Receiver Incremental Tuning offset in hertz, from minus 1000 "
        "to plus 1000. Click and drag, or press Up and Down to "
        "adjust by 50 hertz"));
}

void BottomPanel::buildScoreTable(QWidget* host) {
    // Pascal Panel11 contains ListView1 (vsReport). Three columns —
    // an unlabeled row-name column, "Raw", "Verified" — and three
    // rows — "Pts", "Mult", "Score".
    //
    // QTableWidget's native macOS row + header heights are larger
    // than Pascal's, so the Pascal 68-pixel panel clips. We use a
    // plain grid of QLabels instead — gives perfect control over the
    // line spacing and avoids a heavyweight model/view widget for
    // what is conceptually a 3×3 display.
    auto* frame = new QFrame(host);
    frame->setGeometry(Geom::kHiScoreFrame);
    frame->setFrameStyle(QFrame::StyledPanel | QFrame::Sunken);

    const int frameW = Geom::kHiScoreFrame.width() - 2;
    const int frameH = Geom::kHiScoreFrame.height() - 2;
    constexpr int kCol0W = 44;
    constexpr int kRowH = 22;
    const int colDataW = (frameW - kCol0W) / 2;

    // Panel11's own caption, visible only when the table is hidden (HST).
    hstScoreLabel_ = new QLabel(QStringLiteral("0"), frame);
    hstScoreLabel_->setGeometry(1, 1, frameW, frameH);
    hstScoreLabel_->setAlignment(Qt::AlignCenter);
    {
        // Panel11: MS Sans Serif, Height -19, bold.
        hstScoreLabel_->setFont(dfmFont("Helvetica", 19, true));
    }
    hstScoreLabel_->hide();

    scoreGrid_ = new QWidget(frame);
    scoreGrid_->setGeometry(0, 0, Geom::kHiScoreFrame.width(), Geom::kHiScoreFrame.height());

    auto addCell = [&](int row, int col, const QString& text,
                       Qt::Alignment align = Qt::AlignCenter) {
        auto* lbl = new QLabel(text, scoreGrid_);
        int x = 0;
        int w = 0;
        if (col == 0) {
            x = 4;
            w = kCol0W - 8;
        } else if (col == 1) {
            x = kCol0W;
            w = colDataW;
        } else {
            x = kCol0W + colDataW;
            w = colDataW;
        }
        lbl->setGeometry(x, 4 + row * kRowH, w, kRowH);
        lbl->setAlignment(align);
        return lbl;
    };

    addCell(0, 1, QStringLiteral("Raw"));
    addCell(0, 2, QStringLiteral("Verified"));

    const QStringList rowLabels = {QStringLiteral("Pts"),
                                   QStringLiteral("Mult"),
                                   QStringLiteral("Score")};
    for (int r = 0; r < 3; ++r) {
        addCell(r + 1, 0, rowLabels[r], Qt::AlignLeft | Qt::AlignVCenter);
        scoreCells_[r][0] = addCell(r + 1, 1, QStringLiteral("0"));
        scoreCells_[r][1] = addCell(r + 1, 2, QStringLiteral("0"));
    }
}

void BottomPanel::setScoreTableVisible(bool visible) {
    if (scoreGrid_ != nullptr) {
        scoreGrid_->setVisible(visible);
    }
    if (hstScoreLabel_ != nullptr) {
        hstScoreLabel_->setVisible(!visible);
    }
}

void BottomPanel::setHstScore(int score) {
    if (hstScoreLabel_ != nullptr) {
        hstScoreLabel_->setText(QString::number(score));
    }
}

}  // namespace mr::ui
