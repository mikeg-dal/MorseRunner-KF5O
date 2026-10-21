// Morse Runner — macOS Qt 6 port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reference data for Swift MRCore.Random: the raw MT19937 stream and
// every distribution helper, each from a fresh reseed.

#include "golden_io.h"

#include "core/Random.h"

using namespace golden;

int main(int argc, char** argv) {
    init(argc, argv);
    auto& r = mr::core::Random::instance();
    const unsigned seeds[] = {1u, 42u, 5489u, 0xC90C2086u};
    std::string j = "[";
    bool first = true;
    for (unsigned seed : seeds) {
        std::vector<unsigned> u32;
        r.reseed(seed);
        // Raw stream: two full twists' worth.
        std::mt19937 mt(seed);
        for (int i = 0; i < 1300; ++i) u32.push_back(static_cast<unsigned>(mt()));

        std::vector<float> uni, nrm, gl, ray, ush;
        std::vector<int> ints, poi;
        r.reseed(seed);
        for (int i = 0; i < 200; ++i) uni.push_back(r.uniform01());
        r.reseed(seed);
        for (int n : {1, 2, 3, 6, 7, 8, 13, 100, 1000, 32668}) {
            for (int i = 0; i < 40; ++i) ints.push_back(r.uniformInt(n));
        }
        r.reseed(seed);
        for (int i = 0; i < 201; ++i) nrm.push_back(r.normal());  // odd: ends on a spare
        r.reseed(seed);
        for (int i = 0; i < 100; ++i) gl.push_back(r.gaussLim(0.0f, 300.0f));
        for (int i = 0; i < 100; ++i) gl.push_back(r.gaussLim(20.0f, 10.0f));
        r.reseed(seed);
        for (int i = 0; i < 100; ++i) ray.push_back(r.rayleigh(4.0f));
        r.reseed(seed);
        for (float m : {0.5f, 1.0f, 1.5f, 4.5f}) {
            for (int i = 0; i < 50; ++i) poi.push_back(r.poisson(m));
        }
        r.reseed(seed);
        for (int i = 0; i < 100; ++i) ush.push_back(r.uShaped());

        if (!first) j += ",";
        first = false;
        j += "{\"seed\":" + num(seed) + ",\"u32\":" + arr(u32) + ",\"uniform01\":" + arr(uni)
           + ",\"uniformIntN\":[1,2,3,6,7,8,13,100,1000,32668],\"uniformInt\":" + arr(ints)
           + ",\"normal\":" + arr(nrm) + ",\"gaussLim\":" + arr(gl)
           + ",\"rayleigh\":" + arr(ray) + ",\"poissonMeans\":[0.5,1.0,1.5,4.5],\"poisson\":"
           + arr(poi) + ",\"uShaped\":" + arr(ush) + "}";
    }
    j += "]";
    writeText("core/random.json", j);
    return 0;
}
