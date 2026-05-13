// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "simulation/CallsignDb.h"

#include "core/Constants.h"
#include "core/Random.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <unordered_set>

namespace mr::sim {

namespace {

// Pascal: INDEXSIZE = Sqr(37) + 1 = 1370; INDEXBYTES = 5480.
constexpr int kIndexEntries = 37 * 37 + 1;
constexpr std::size_t kIndexBytes = kIndexEntries * sizeof(std::int32_t);

}  // namespace

bool CallsignDb::loadFromFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) {
        return false;
    }
    const std::streamoff fileSize = f.tellg();
    f.seekg(0, std::ios::beg);
    if (fileSize < static_cast<std::streamoff>(kIndexBytes)) {
        return false;
    }

    // Read and validate the header. Pascal checks the first and last
    // entries match expected sentinel values; we do the same.
    std::vector<std::int32_t> header(kIndexEntries);
    f.read(reinterpret_cast<char*>(header.data()),
           static_cast<std::streamsize>(kIndexBytes));
    if (!f) {
        return false;
    }
    if (header.front() != static_cast<std::int32_t>(kIndexBytes)
        || header.back() != static_cast<std::int32_t>(fileSize)) {
        return false;
    }

    // Read the data block (null-terminated callsign records).
    const std::size_t dataLen =
        static_cast<std::size_t>(fileSize) - kIndexBytes;
    std::vector<char> data(dataLen);
    f.read(data.data(), static_cast<std::streamsize>(dataLen));
    if (!f) {
        return false;
    }

    // Walk the null-terminated records into a temporary vector, then
    // dedup. Pascal sorts and compares neighbours — an unordered_set
    // is O(n) which is faster and gives the same result.
    std::vector<std::string> picked;
    picked.reserve(20000);   // Pascal's L.Capacity := 20000 hint
    std::unordered_set<std::string> seen;
    seen.reserve(20000);

    std::size_t i = 0;
    while (i < dataLen) {
        const std::size_t start = i;
        while (i < dataLen && data[i] != '\0') {
            ++i;
        }
        if (i > start) {
            std::string call(&data[start], i - start);
            if (seen.insert(call).second) {
                picked.push_back(std::move(call));
            }
        }
        ++i;  // skip the null
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        calls_ = std::move(picked);
    }
    return true;
}

std::string CallsignDb::pickCall(mr::core::Random& rng) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (calls_.empty()) {
        // Pascal CallLst.PickCall fallback: returns the literal
        // 'P29SX' when the database is missing or failed to load.
        return std::string("P29SX");
    }
    const int idx = rng.uniformInt(static_cast<int>(calls_.size()));
    return calls_[static_cast<std::size_t>(idx)];
}

std::string CallsignDb::pickAndRemoveCall(mr::core::Random& rng) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (calls_.empty()) {
        return std::string("P29SX");
    }
    const int idx = rng.uniformInt(static_cast<int>(calls_.size()));
    std::string out = std::move(calls_[static_cast<std::size_t>(idx)]);
    // Swap-pop: O(1) removal without preserving order. Order doesn't
    // matter — Pascal `Calls.Delete(Idx)` is O(n) but the difference
    // is irrelevant since HST is the only mode that calls this.
    calls_[static_cast<std::size_t>(idx)] = std::move(calls_.back());
    calls_.pop_back();
    return out;
}

std::size_t CallsignDb::size() const noexcept {
    std::lock_guard<std::mutex> lock(mutex_);
    return calls_.size();
}

}  // namespace mr::sim
