# Constants citations

Every numeric literal in `Swift/Sources/MRCore/Constants.swift` traces back
to a specific location in the original Delphi source. This table is the authoritative
audit trail.

The port preserves these values exactly to keep audio output and
simulation behavior indistinguishable from the original. The values are grouped as `MathK`, `AudioK`, `DspK`, `SimK` and
`ScoringK`, and the reference-data tests check them end to end.

| Constant | Value | Pascal origin | Reason |
|---|---|---|---|
| `AudioK.sampleRate` | 11025 Hz | `Ini.pas` `DEFAULTRATE` | Legacy Windows Sound System rate; all filters, ramps, BFO tables computed against it. |
| `AudioK.bufferExpDefault` | 3 | `Ini.pas::FromIni` (`BufSize := 64 shl V`) | INI key "BufSize" default; samples = 64<<3 = 512 (~46 ms). |
| `AudioK.startupSkipBlocks` | 6 | `Contest.pas::GetAudio` (`if BlockNumber < 6 then Exit`) | Mask startup pop while filters settle. |
| `AudioK.filterSwapBlocks` | 10 | `Contest.pas::GetAudio` (`if (BlockNumber mod 10) = 0 then SwapFilters`) | Ping-pong cadence to avoid the audible click that would come from periodically resetting a long delay line. |
| `DspK.noiseAmp` | 6000.0 | `Contest.pas::GetAudio` (`NOISEAMP = 6000`) | Linear-PCM noise floor; sits ~−15 dBFS so AGC has range. |
| `DspK.qrnSpikePerSampleProb` | 0.01 | `Contest.pas::GetAudio` (`if Random < 0.01 then ReIm.Re[i] := 60 * NOISEAMP * (Random-0.5)`) | Per-sample QRN spike rate. |
| `DspK.qrnSpikeAmpMul` | 60.0 | same | Spike amplitude multiplier vs noise floor. |
| `DspK.qrnBurstPerBlockProb` | 0.01 | `Contest.pas::GetAudio` (`if Random < 0.01 then Stations.AddQrn`) | Per-block QRN station spawn. |
| `DspK.qrmSpawnPerBlockProb` | 0.0002 | `Contest.pas::GetAudio` (`if Ini.Qrm and (Random < 0.0002)`) | Per-block QRM station spawn (~once per 5000 blocks ≈ 4 min). |
| `DspK.qskAttackCoeff` | 0.997 | `Contest.pas::GetAudio` (`Rfg := Rfg * 0.997 + 0.003`) | QSK self-monitor recovery; ≈ 333-block (~15 s) time constant. |
| `DspK.qskReleaseAdd` | 0.003 | same | Recovery floor coefficient. |
| `DspK.riseTimeSeconds` | 0.005 | `VCL/MorseKey.pas::Create` (`RiseTime := 0.005`) | 5 ms Blackman-Harris key ramp; eliminates audible CW clicks. |
| `DspK.blackmanHarrisStretch` | 2.7 | `VCL/MorseKey.pas::MakeRamp` (`RampLen := Round(2.7 * FRiseTime * Rate)`) | Stretches the BH step response to match the requested rise time. |
| `DspK.filterPointsRatio` | 0.7 | `Contest.pas::Create` (`Filt.Points := Round(0.7 * DEFAULTRATE / Ini.BandWidth)`) | Empirical points-per-bandwidth coefficient for the moving-average LPF. |
| `DspK.filterPasses` | 3 | `Contest.pas::Create` (`Filt.Passes := 3`) | 3-pass moving average approximates Gaussian closely enough for radio audio. |
| `DspK.filterGainRefBw` | 500.0 | `Contest.pas::Create` (`Filt.GainDb := 10 * Log10(500/Ini.Bandwidth)`) | Reference bandwidth at which net gain is 0 dB. |
| `DspK.agcNoiseInDb` | 76.0 | `Contest.pas::Create` (`Agc.NoiseInDb := 76`) | AGC input noise-floor target. |
| `DspK.agcNoiseOutDb` | 76.0 | `Contest.pas::Create` (`Agc.NoiseOutDb := 76`) | AGC output noise-floor target (matched → unity gain at noise floor). |
| `DspK.agcAttackSamples` | 155 | `Contest.pas::Create` (`Agc.AttackSamples := 155`) | ≈ 14 ms at 11025 Hz. |
| `DspK.agcHoldSamples` | 155 | `Contest.pas::Create` (`Agc.HoldSamples := 155`) | Symmetric hold time. |
| `SimK.fullPatience` | 5 | `DxOper.pas` (`FULL_PATIENCE = 5`) | Operator patience for normal QSO states. |
| `SimK.needQsoPatienceMean` | 4.0 | `DxOper.pas::SetState` (`Patience := Round(RndRayleigh(4))`) | Rayleigh-distributed patience when entering NeedQso. |
| `SimK.dxAmpBase` | 9000.0 | `DxStn.pas::CreateStation` (`Amplitude := 9000 + 18000 * (1 + RndUShaped)`) | DX station amplitude floor. |
| `SimK.dxAmpSpread` | 18000.0 | same | Spread coefficient. |
| `SimK.dxPitchSpreadHz` | 300.0 | `DxStn.pas` (`Pitch := Round(RndGaussLim(0, 300))`) | Per-station BFO offset SD/limit. |
| `SimK.lidRstErrorProb` | 0.03 | `DxStn.pas` (`if Ini.Lids and (Random < 0.03)`) | Chance a LID sends RST other than 599. |
| `SimK.lidNrErrorProb` | 0.10 | `DxStn.pas` (`NrWithError := Ini.Lids and (Random < 0.1)`) | Chance a LID corrupts NR. |
| `SimK.cutZeroAsOProb` | 0.40 | `Station.pas::NrAsText` (`if Random < 0.4 then ... 'O'`) | Cut-number "0"→"O" probability. |
| `SimK.cutZeroAsTProb` | 0.97 | `Station.pas::NrAsText` (`else if Random < 0.97 then ... 'T'`) | Cut-number "0"→"T" fallback. |
| `SimK.cutNineAsNProb` | 0.97 | `Station.pas::NrAsText` (`if Random < 0.97 then ... 'N'`) | Cut-number "9"→"N" probability. |
| `SimK.levSubstCost` | 2 | `DxOper.pas::IsMyCall` (`W_X = 2; W_Y = 2; W_D = 2`) | Levenshtein insertion/deletion/substitution cost. |
| `SimK.levMatchThresh` | 2 | `DxOper.pas::IsMyCall` (`1,2: Result := mcAlmost`) | Penalty threshold for "Almost". |
| `SimK.repeatProb` | 0.10 | `DxOper.pas::SetState` (`if ... (Random < 0.1) then RepeatCnt := 2`) | Chance the DX repeats its first response. |
| `SimK.mishearStandardProb` | 0.01 | `DxOper.pas::IsMyCall` (`mcYes: if Random < 0.01 then Result := mcAlmost`) | LID accepts correct call as almost. |
| `SimK.mishearLidProb` | 0.04 | `DxOper.pas::IsMyCall` (`mcAlmost: if Random < 0.04 then Result := mcYes`) | LID accepts almost as correct. |
| `MainWindowController` content width | 700 | `Main.dfm` `ClientWidth` | Fixed window width. |
| `MainWindowController` content height | 413 | `Main.dfm` `ClientHeight` | Fixed window height. |
| `QsoLog.histogramBins` | 48 | `Log.pas::PaintHisto` (`array[0..47]`) | 4 hours × 60 / 5 min. |
| `QsoLog.histogramBinMinutes` | 5 | `Log.pas::PaintHisto` (`Trunc(QsoList[i].T * 1440) div 5`) | Bin width. |
| `EngineBridge` UI timer | 30 | (new) | GUI update throttle. |
| `ScoringK.crc32Seed` | 0xC90C2086 | inferred from `VCL/Crc32.pas` use site in `ScoreDlg` | CRC32 seed for score-string verification. |
