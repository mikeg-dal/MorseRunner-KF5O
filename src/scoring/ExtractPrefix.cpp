// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "scoring/ExtractPrefix.h"

#include <cctype>
#include <string>

namespace mr::scoring {

namespace {

constexpr bool isDigit(char c) noexcept { return c >= '0' && c <= '9'; }
constexpr bool isLetter(char c) noexcept {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

// Pascal: StringReplace(Call, what, '', []) replaces the FIRST
// occurrence only. Our helper mirrors that — using std::string::find +
// erase, not a loop — because Pascal's portable-suffix stripping
// depends on order (the FIRST hit decides which suffix wins).
void replaceFirst(std::string& s, std::string_view from,
                  std::string_view to) {
    const auto p = s.find(from);
    if (p == std::string::npos) {
        return;
    }
    s.replace(p, from.size(), to);
}

// Pascal: StringReplace(Call, '//', '/', [rfReplaceAll]) — replaces
// ALL occurrences. Loop until no more matches.
void replaceAll(std::string& s, std::string_view from,
                std::string_view to) {
    std::size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
        pos += to.size();
    }
}

}  // namespace

std::string extractPrefix(std::string_view callIn) {
    // Pascal pre-strips modifiers by appending '|' as a sentinel so
    // the suffix patterns can match end-of-string explicitly. We
    // mirror that exactly.
    std::string call(callIn);
    call += '|';
    replaceFirst(call, "/QRP|", "");
    replaceFirst(call, "/MM|",  "");
    replaceFirst(call, "/M|",   "");
    replaceFirst(call, "/P|",   "");
    replaceFirst(call, "|",     "");
    replaceAll(call, "//", "/");
    if (call.size() < 2) {
        return {};
    }

    std::string dig;        // Pascal: single-digit alternate
    std::string result;

    // Pascal indexes strings 1-based; `p = Pos('/', Call)` returns 0
    // when no slash is present, otherwise the 1-based slash position.
    // We work in 0-based but preserve the Pascal branches.
    const auto p = call.find('/');
    if (p == std::string::npos) {
        result = call;
    } else if (p == 0) {
        // Pascal: p == 1 (slash at start). Result = Copy(Call, 2, ..).
        result = call.substr(1);
    } else if (p == call.size() - 1) {
        // Pascal: p == Length(Call) (slash at end). Result = chars
        // before the slash.
        result = call.substr(0, p);
    } else {
        const std::string s1 = call.substr(0, p);
        const std::string s2 = call.substr(p + 1);
        if (s1.size() == 1 && isDigit(s1[0])) {
            dig = s1;
            result = s2;
        } else if (s2.size() == 1 && isDigit(s2[0])) {
            dig = s2;
            result = s1;
        } else if (s1.size() <= s2.size()) {
            // Pascal: <= so ties favor S1.
            result = s1;
        } else {
            result = s2;
        }
    }
    if (result.find('/') != std::string::npos) {
        return {};
    }

    // Pascal: for p := Length(Result) downto 3 do
    //           if Result[p] in DIGITS then Break
    //           else Delete(Result, p, 1);
    // Loop is from end (1-based Length) down to 3 (inclusive),
    // deleting trailing letters until we find a digit. The "down to 3"
    // ensures we always keep at least 2 characters (Pascal indices 1
    // and 2). The loop variable p stops referring to the same position
    // because we shrink the string, but Pascal's `Result[p]` is
    // re-evaluated each iteration.
    while (result.size() >= 3) {
        const char last = result.back();
        if (isDigit(last)) {
            break;
        }
        // Drop the trailing letter (or other non-digit) and try again.
        result.pop_back();
    }

    if (result.empty()) {
        return {};
    }

    // Pascal: if not (Result[Length(Result)] in DIGITS) then
    //           Result := Result + '0';
    if (!isDigit(result.back())) {
        result += '0';
    }
    // Pascal: if Dig <> '' then Result[Length(Result)] := Dig[1];
    if (!dig.empty()) {
        result.back() = dig[0];
    }
    // Pascal: Result := Copy(Result, 1, 5);
    if (result.size() > 5) {
        result.resize(5);
    }
    return result;
}

}  // namespace mr::scoring
