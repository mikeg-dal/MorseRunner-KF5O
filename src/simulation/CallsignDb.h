// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pascal CallLst.pas port. Master.dta is a packed binary:
//   - 1370 * sizeof(int32) header — first entry equals header size in
//     bytes (5480), last entry equals total file size. The middle 1368
//     entries are offsets into the data block; we don't use them
//     because we just walk the whole null-terminated string section.
//   - data block: one null-terminated ASCII callsign per record.
// On load we dedup (Pascal also dedups via Sort+StrComp neighbour
// compare) and stash the calls in a flat vector.
//
// Threading: load happens once at startup. Pascal blocks the GUI
// during the parse; our loader runs on its own thread ("mr-dbload")
// and the CallsignSource API used by Contest is thread-safe for
// concurrent reads.

#pragma once

#include "simulation/CallsignSource.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace mr::sim {

class CallsignDb : public CallsignSource {
public:
    // Parses the Master.dta file at `path`. Returns true on success;
    // on failure the database stays empty and pickCall() falls back
    // to literal "P29SX" (Pascal parity).
    [[nodiscard]] bool loadFromFile(const std::string& path);

    // CallsignSource interface ─────────────────────────────────────
    [[nodiscard]] std::string pickCall(mr::core::Random& rng) override;
    [[nodiscard]] std::string pickAndRemoveCall(mr::core::Random& rng) override;

    [[nodiscard]] std::size_t size() const noexcept;

private:
    mutable std::mutex mutex_;
    std::vector<std::string> calls_;
};

}  // namespace mr::sim
