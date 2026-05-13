// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

namespace mr::core {

// Sets the current pthread's name. Call once from the entry of each
// QThread::run() override (or its first slot invocation) so Instruments,
// Console, and `ps -M` show useful identifiers instead of "Thread-3".
//
// Names are limited to 15 chars + NUL on macOS — we keep them short:
// "mr-main", "mr-sim", "mr-audio", "mr-wav", "mr-dbload".
void setCurrentThreadName(const char* name) noexcept;

}  // namespace mr::core
