// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/Messages.h"

#include <array>

namespace mr::sim {

namespace {

// One slot per Message enum value. Order MUST match the enum exactly —
// the lookup is `templates[static_cast<size_t>(m)]`. The strings are
// verbatim from Station.pas::SendMsg's case statement, including the
// peculiarities (extra trailing space in 'msqQsy' becomes `<his>  QSY
// QSY` — note the two spaces between `<his>` and QSY).
constexpr std::array<std::string_view, kMessageCount> kTemplates = {{
    /* None        */ "",
    /* Cq          */ "CQ <my> TEST",
    /* Nr          */ "<#>",
    /* Tu          */ "TU",
    /* MyCall      */ "<my>",
    /* HisCall     */ "<his>",
    /* B4          */ "QSO B4",
    /* Qm          */ "?",
    /* Nil         */ "NIL",
    /* Garbage     */ "",
    /* R_Nr        */ "R <#>",
    /* R_Nr2       */ "R <#> <#>",
    /* DeMyCall1   */ "DE <my>",
    /* DeMyCall2   */ "DE <my> <my>",
    /* DeMyCallNr1 */ "DE <my> <#>",
    /* DeMyCallNr2 */ "DE <my> <my> <#>",
    /* NrQm        */ "NR?",
    /* LongCq      */ "CQ CQ TEST <my> <my> TEST",
    /* MyCallNr2   */ "<my> <my> <#>",
    /* Qrl         */ "QRL?",
    /* Qrl2        */ "QRL?   QRL?",
    /* Qsy         */ "<his>  QSY QSY",
    /* Agn         */ "AGN",
}};

constexpr std::array<std::string_view, kMessageCount> kNames = {{
    "None", "Cq", "Nr", "Tu", "MyCall", "HisCall", "B4", "Qm", "Nil",
    "Garbage", "R_Nr", "R_Nr2", "DeMyCall1", "DeMyCall2", "DeMyCallNr1",
    "DeMyCallNr2", "NrQm", "LongCq", "MyCallNr2", "Qrl", "Qrl2", "Qsy",
    "Agn",
}};

static_assert(kTemplates.size() == kMessageCount, "templates table out of sync");
static_assert(kNames.size() == kMessageCount, "names table out of sync");

}  // namespace

std::string_view templateFor(Message m) noexcept {
    const auto idx = static_cast<std::size_t>(m);
    if (idx >= kTemplates.size()) {
        return {};
    }
    return kTemplates[idx];
}

std::string_view nameOf(Message m) noexcept {
    const auto idx = static_cast<std::size_t>(m);
    if (idx >= kNames.size()) {
        return "Unknown";
    }
    return kNames[idx];
}

}  // namespace mr::sim
