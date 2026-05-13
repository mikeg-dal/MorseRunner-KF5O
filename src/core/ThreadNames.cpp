// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "core/ThreadNames.h"

#include <pthread.h>

namespace mr::core {

void setCurrentThreadName(const char* name) noexcept {
    // On macOS, pthread_setname_np takes only the name (no thread handle —
    // the kernel always names the *current* thread) and silently truncates
    // beyond 63 characters. We rely on callers to keep names ≤15 chars so
    // they show up correctly in legacy tools like `ps -M`.
    (void) pthread_setname_np(name);
}

}  // namespace mr::core
