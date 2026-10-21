// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "ui/widgets/LogView.h"

#include <QFont>
#include <QScrollBar>
#include <QTextBlockFormat>
#include <QTextCharFormat>
#include <QTextCursor>

#include <algorithm>

namespace mr::ui {

namespace {

constexpr int kErrorTagLength = 3;

QString headerLineFor(LogView::HeaderStyle style) {
    // Pascal: Log.pas::Clear adds the underlined+blue header line.
    // Column widths match the row format below it so the columns
    // align visually.
    switch (style) {
        case LogView::HeaderStyle::HstScore:
            return QStringLiteral(
                " UTC       Call          Recv      Sent      Score  Chk");
        case LogView::HeaderStyle::WpxPrefix:
        default:
            return QStringLiteral(
                " UTC       Call          Recv      Sent      Pref   Chk");
    }
}

}  // namespace

LogView::LogView(QWidget* parent) : QTextEdit(parent) {
    setReadOnly(true);
    setFrameStyle(QFrame::NoFrame);
    // Pascal RichEdit1: Courier New 13pt. Menlo is the closest
    // monospace face shipped with macOS; 13pt matches the .dfm.
    QFont mono(QStringLiteral("Menlo"), 13);
    mono.setStyleHint(QFont::Monospace);
    setFont(mono);
    setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    setLineWrapMode(QTextEdit::NoWrap);
    setHeader(HeaderStyle::WpxPrefix);
}

void LogView::setHeader(HeaderStyle style) {
    QTextEdit::clear();
    QTextCursor cursor(textCursor());
    QTextCharFormat fmt;
    fmt.setFontUnderline(true);
    fmt.setForeground(Qt::blue);
    cursor.insertText(headerLineFor(style), fmt);
}

void LogView::appendQsoRow(const QString& row, const QString& errorTag) {
    QTextCursor cursor(textCursor());
    cursor.movePosition(QTextCursor::End);
    cursor.insertBlock();

    QTextCharFormat plain;
    QTextCharFormat error;
    error.setForeground(Qt::red);

    // The error tag occupies the trailing 3 chars of the row; we
    // split the line so the red colouring lands only on that span.
    const qsizetype trailing =
        std::min<qsizetype>(kErrorTagLength, row.size());
    const QString prefix = row.left(row.size() - trailing);
    const QString suffix = row.right(trailing);
    cursor.insertText(prefix, plain);
    cursor.insertText(suffix, error);

    // Auto-scroll to the newest row.
    verticalScrollBar()->setValue(verticalScrollBar()->maximum());
    (void) errorTag;  // reserved for Phase E (e.g. tooltip annotations)
}

void LogView::replaceLastQsoRow(const QString& row) {
    QTextCursor cursor(document());
    cursor.movePosition(QTextCursor::End);
    if (cursor.blockNumber() == 0) {
        return;  // only the header line
    }
    cursor.movePosition(QTextCursor::StartOfBlock);
    cursor.movePosition(QTextCursor::PreviousCharacter, QTextCursor::KeepAnchor);
    cursor.movePosition(QTextCursor::End, QTextCursor::KeepAnchor);
    cursor.removeSelectedText();
    appendQsoRow(row, row.right(kErrorTagLength));
}

void LogView::clear() {
    QTextEdit::clear();
    setHeader(HeaderStyle::WpxPrefix);
}

}  // namespace mr::ui
