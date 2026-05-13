# Constants citations

Every numeric literal in `src/core/Constants.h` traces back to a specific
location in the original Delphi source. This table is the authoritative
audit trail.

The port preserves these values exactly to keep audio output and
simulation behavior indistinguishable from the original.

| Constant | Value | Pascal origin | Reason |
|---|---|---|---|
| `Audio::kSampleRate` | 11025 Hz | `Ini.pas` `DEFAULTRATE` | Legacy Windows Sound System rate; all filters, ramps, BFO tables computed against it. |
| `Audio::kBufferExpDefault` | 3 | `Ini.pas::FromIni` (`BufSize := 64 shl V`) | INI key "BufSize" default; samples = 64<<3 = 512 (~46 ms). |
| `Audio::kStartupSkipBlocks` | 6 | `Contest.pas::GetAudio` (`if BlockNumber < 6 then Exit`) | Mask startup pop while filters settle. |
| `Audio::kFilterSwapBlocks` | 10 | `Contest.pas::GetAudio` (`if (BlockNumber mod 10) = 0 then SwapFilters`) | Ping-pong cadence to avoid the audible click that would come from periodically resetting a long delay line. |
| `Dsp::kNoiseAmp` | 6000.0 | `Contest.pas::GetAudio` (`NOISEAMP = 6000`) | Linear-PCM noise floor; sits ~−15 dBFS so AGC has range. |
| `Dsp::kQrnSpikePerSampleProb` | 0.01 | `Contest.pas::GetAudio` (`if Random < 0.01 then ReIm.Re[i] := 60 * NOISEAMP * (Random-0.5)`) | Per-sample QRN spike rate. |
| `Dsp::kQrnSpikeAmpMul` | 60.0 | same | Spike amplitude multiplier vs noise floor. |
| `Dsp::kQrnBurstPerBlockProb` | 0.01 | `Contest.pas::GetAudio` (`if Random < 0.01 then Stations.AddQrn`) | Per-block QRN station spawn. |
| `Dsp::kQrmSpawnPerBlockProb` | 0.0002 | `Contest.pas::GetAudio` (`if Ini.Qrm and (Random < 0.0002)`) | Per-block QRM station spawn (~once per 5000 blocks ≈ 4 min). |
| `Dsp::kQskAttackCoeff` | 0.997 | `Contest.pas::GetAudio` (`Rfg := Rfg * 0.997 + 0.003`) | QSK self-monitor recovery; ≈ 333-block (~15 s) time constant. |
| `Dsp::kQskReleaseAdd` | 0.003 | same | Recovery floor coefficient. |
| `Dsp::kRiseTimeSeconds` | 0.005 | `VCL/MorseKey.pas::Create` (`RiseTime := 0.005`) | 5 ms Blackman-Harris key ramp; eliminates audible CW clicks. |
| `Dsp::kBlackmanHarrisStretch` | 2.7 | `VCL/MorseKey.pas::MakeRamp` (`RampLen := Round(2.7 * FRiseTime * Rate)`) | Stretches the BH step response to match the requested rise time. |
| `Dsp::kFilterPointsRatio` | 0.7 | `Contest.pas::Create` (`Filt.Points := Round(0.7 * DEFAULTRATE / Ini.BandWidth)`) | Empirical points-per-bandwidth coefficient for the moving-average LPF. |
| `Dsp::kFilterPasses` | 3 | `Contest.pas::Create` (`Filt.Passes := 3`) | 3-pass moving average approximates Gaussian closely enough for radio audio. |
| `Dsp::kFilterGainRefBw` | 500.0 | `Contest.pas::Create` (`Filt.GainDb := 10 * Log10(500/Ini.Bandwidth)`) | Reference bandwidth at which net gain is 0 dB. |
| `Dsp::kAgcNoiseInDb` | 76.0 | `Contest.pas::Create` (`Agc.NoiseInDb := 76`) | AGC input noise-floor target. |
| `Dsp::kAgcNoiseOutDb` | 76.0 | `Contest.pas::Create` (`Agc.NoiseOutDb := 76`) | AGC output noise-floor target (matched → unity gain at noise floor). |
| `Dsp::kAgcAttackSamples` | 155 | `Contest.pas::Create` (`Agc.AttackSamples := 155`) | ≈ 14 ms at 11025 Hz. |
| `Dsp::kAgcHoldSamples` | 155 | `Contest.pas::Create` (`Agc.HoldSamples := 155`) | Symmetric hold time. |
| `Sim::kFullPatience` | 5 | `DxOper.pas` (`FULL_PATIENCE = 5`) | Operator patience for normal QSO states. |
| `Sim::kNeedQsoPatienceMean` | 4.0 | `DxOper.pas::SetState` (`Patience := Round(RndRayleigh(4))`) | Rayleigh-distributed patience when entering NeedQso. |
| `Sim::kDxAmpBase` | 9000.0 | `DxStn.pas::CreateStation` (`Amplitude := 9000 + 18000 * (1 + RndUShaped)`) | DX station amplitude floor. |
| `Sim::kDxAmpSpread` | 18000.0 | same | Spread coefficient. |
| `Sim::kDxPitchSpreadHz` | 300.0 | `DxStn.pas` (`Pitch := Round(RndGaussLim(0, 300))`) | Per-station BFO offset SD/limit. |
| `Sim::kLidRstErrorProb` | 0.03 | `DxStn.pas` (`if Ini.Lids and (Random < 0.03)`) | Chance a LID sends RST other than 599. |
| `Sim::kLidNrErrorProb` | 0.10 | `DxStn.pas` (`NrWithError := Ini.Lids and (Random < 0.1)`) | Chance a LID corrupts NR. |
| `Sim::kCutZeroAsO_Prob` | 0.40 | `Station.pas::NrAsText` (`if Random < 0.4 then ... 'O'`) | Cut-number "0"→"O" probability. |
| `Sim::kCutZeroAsT_Prob` | 0.97 | `Station.pas::NrAsText` (`else if Random < 0.97 then ... 'T'`) | Cut-number "0"→"T" fallback. |
| `Sim::kCutNineAsN_Prob` | 0.97 | `Station.pas::NrAsText` (`if Random < 0.97 then ... 'N'`) | Cut-number "9"→"N" probability. |
| `Sim::kLevSubstCost` | 2 | `DxOper.pas::IsMyCall` (`W_X = 2; W_Y = 2; W_D = 2`) | Levenshtein insertion/deletion/substitution cost. |
| `Sim::kLevMatchThresh` | 2 | `DxOper.pas::IsMyCall` (`1,2: Result := mcAlmost`) | Penalty threshold for "Almost". |
| `Sim::kRepeatProb` | 0.10 | `DxOper.pas::SetState` (`if ... (Random < 0.1) then RepeatCnt := 2`) | Chance the DX repeats its first response. |
| `Sim::kMishearStandardProb` | 0.01 | `DxOper.pas::IsMyCall` (`mcYes: if Random < 0.01 then Result := mcAlmost`) | LID accepts correct call as almost. |
| `Sim::kMishearLidProb` | 0.04 | `DxOper.pas::IsMyCall` (`mcAlmost: if Random < 0.04 then Result := mcYes`) | LID accepts almost as correct. |
| `Ui::kMainWindowWidth` | 700 | `Main.dfm` `ClientWidth` | Fixed window width. |
| `Ui::kMainWindowHeight` | 413 | `Main.dfm` `ClientHeight` | Fixed window height. |
| `Ui::kHistogramBins` | 48 | `Log.pas::PaintHisto` (`array[0..47]`) | 4 hours × 60 / 5 min. |
| `Ui::kHistogramBinMinutes` | 5 | `Log.pas::PaintHisto` (`Trunc(QsoList[i].T * 1440) div 5`) | Bin width. |
| `Ui::kGuiUpdateHz` | 30 | (new) | GUI update throttle. |
| `Scoring::kCrc32Seed` | 0xC90C2086 | inferred from `VCL/Crc32.pas` use site in `ScoreDlg` | CRC32 seed for score-string verification. |
