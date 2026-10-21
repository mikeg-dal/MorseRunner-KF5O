// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Every numeric constant of the simulator, ported from the C++
// src/core/Constants.h, which cites each one back to the Pascal source
// (docs/constants-citations.md). Types match the C++ exactly (Float vs
// Double matters for bit-exact output).

public enum MathK {
    public static let pi: Double = 3.141592653589793
    public static let twoPi: Double = 2.0 * pi
}

public enum AudioK {
    public static let sampleRate = 11025
    public static let bufferExpMin = 1
    public static let bufferExpMax = 5
    public static let bufferExpDefault = 3
    /// Pascal Ini.pas: `BufSize := 64 shl V`.
    public static func bufferSamples(forExp exp: Int) -> Int { 64 << exp }
    public static let defaultBufferSamples = bufferSamples(forExp: bufferExpDefault)  // 512
    /// Pascal Contest.GetAudio: `if BlockNumber < 6 then Exit`.
    public static let startupSkipBlocks = 6
    /// PingPongFilter cadence (Pascal Contest.GetAudio SwapFilters).
    public static let filterSwapBlocks = 10

    /// Duration of `blocks` audio blocks of `bufSize` samples, in seconds.
    public static func blocksToSeconds(_ blocks: Double,
                                       bufSize: Int = defaultBufferSamples) -> Double {
        blocks * Double(bufSize) / Double(sampleRate)
    }

    /// Pascal RndFunc.pas SecondsToBlocks: `Round(DEFAULTRATE / BufSize *
    /// Sec)` with Delphi's round-half-to-even (C++ Constants.h,
    /// std::nearbyint). `bufSize` must be positive and the result must be
    /// finite and fit in an Int (see delphiRound).
    public static func secondsToBlocks(_ seconds: Double,
                                       bufSize: Int = defaultBufferSamples) -> Int {
        precondition(bufSize > 0, "AudioK.secondsToBlocks: bufSize must be positive")
        return delphiRound(Double(sampleRate) / Double(bufSize) * seconds)
    }
}

public enum DspK {
    public static let noiseAmp: Float = 6000.0
    public static let noiseChannelGainMul: Float = 3.0
    public static let qrnSpikePerSampleProb: Float = 0.01
    public static let qrnSpikeAmpMul: Float = 60.0
    public static let qrnBurstPerBlockProb: Float = 0.01
    public static let qrnBurstAmpBase: Float = 1.0e5
    public static let qrnBurstEnvelopeSpikeProb: Float = 0.01
    public static let qrmSpawnPerBlockProb: Float = 0.0002
    public static let qrmPitchSpreadHz: Float = 300.0
    public static let qrmAmpBase: Float = 5000.0
    public static let qrmAmpRange: Float = 25000.0
    public static let qrmWpmBase = 30
    public static let qrmWpmRange = 20
    public static let qskAttackCoeff: Float = 0.997
    public static let qskReleaseAdd: Float = 0.003
    public static let selfMonGainSliderZero: Float = 0.75
    public static let selfMonGainScale: Float = 4.0
    public static let riseTimeSeconds: Double = 0.005
    public static let blackmanHarrisStretch: Double = 2.7
    public static let morseUnitSecondsCoef: Double = 0.1
    public static let morseUnitsPerWpmRef = 12
    public static let blackmanHarrisA0: Double = 0.35875
    public static let blackmanHarrisA1: Double = 0.48829
    public static let blackmanHarrisA2: Double = 0.14128
    public static let blackmanHarrisA3: Double = 0.01168
    public static let filterPointsRatio: Float = 0.7
    public static let filterPasses = 3
    public static let filterGainRefBw: Float = 500.0
    public static let agcNoiseInDb: Float = 76.0
    public static let agcNoiseOutDb: Float = 76.0
    public static let agcAttackSamples = 155
    public static let agcHoldSamples = 155
    public static let qsbBandwidthBase: Float = 0.1
    public static let qsbBandwidthSpread: Float = 0.5
    public static let flutterProb: Float = 0.3
    public static let flutterBwBase: Float = 3.0
    public static let flutterBwSpread: Float = 30.0
}

public enum SimK {
    public static let fullPatience = 5
    public static let needQsoPatienceMean: Float = 4.0
    public static let dxAmpBase: Float = 9000.0
    public static let dxAmpSpread: Float = 18000.0
    public static let dxPitchSpreadHz: Float = 300.0
    public static let lidRstErrorProb: Float = 0.03
    public static let lidNrErrorProb: Float = 0.10
    public static let lidRstBase = 559
    public static let lidRstStep = 10
    public static let lidRstCount = 4
    public static let cutZeroAsOProb: Float = 0.40
    public static let cutZeroAsTProb: Float = 0.97
    public static let cutNineAsNProb: Float = 0.97
    public static let levSubstCost = 2
    public static let levInsCost = 2
    public static let levDelCost = 2
    public static let levMatchThresh = 2
    public static let repeatProb: Float = 0.10
    public static let repeatCount = 2
    public static let mishearStandardProb: Float = 0.01
    public static let mishearLidProb: Float = 0.04
    public static let callerSpawnRateActivityDivisor: Float = 2.0
}

public enum ScoringK {
    /// Pascal VCL/Crc32.pas seed for the PopupScoreWpx stamp.
    public static let crc32Seed: UInt32 = 0xC90C_2086
    /// ExtractPrefix keeps at least this many bytes when dropping
    /// trailing letters, and cuts the result to maxPrefixLen bytes.
    public static let minPrefixLen = 2
    public static let maxPrefixLen = 5
    /// CallToScore costs per encoded symbol, and the -1 start value.
    public static let hstDotCost = 2
    public static let hstDashCost = 4
    public static let hstSpaceCost = 2
    public static let hstStartPenalty = 1
}
