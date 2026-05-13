# Pascal → C++ symbol mapping

Authoritative cross-reference. When a port file lands, add its row here so
reviewers can grep for the Pascal origin.

| Pascal symbol | Pascal file | C++ port symbol | C++ port file |
|---|---|---|---|
| `TContest` / `Tst` | `Contest.pas` | `Sim::Contest` | `src/simulation/Contest.{h,cpp}` |
| `TContest.GetAudio` | `Contest.pas` | `Sim::Contest::renderNextBlock` | `src/simulation/Contest.cpp` |
| `TStation` (base) | `Station.pas` | `Sim::Station` | `src/simulation/Station.{h,cpp}` |
| `TMyStation` | `MyStn.pas` | `Sim::MyStation` | `src/simulation/MyStation.{h,cpp}` |
| `TDxStation` | `DxStn.pas` | `Sim::DxStation` | `src/simulation/DxStation.{h,cpp}` |
| `TDxOperator` (FSM) | `DxOper.pas` | `Sim::DxOperator` | `src/simulation/DxOperator.{h,cpp}` |
| `IsMyCall` (Levenshtein DP) | `DxOper.pas` | `Sim::isMyCall` | `src/simulation/IsMyCall.{h,cpp}` |
| `TQrnStation` / `TQrmStation` | `QrnStn.pas` / `QrmStn.pas` | `Sim::QrnStation` / `Sim::QrmStation` | `src/simulation/QrnStation.*` / `QrmStation.*` |
| `TStations` collection | `StnColl.pas` | `Sim::StationCollection` | `src/simulation/StationCollection.{h,cpp}` |
| `TStationMessage` enum | `Station.pas` | `Sim::Message` | `src/simulation/Messages.h` |
| `NrAsText` | `Station.pas` | `Sim::NumberFormat::nrAsText` | `src/simulation/NumberFormat.{h,cpp}` |
| `TKeyer` | `VCL/MorseKey.pas` | `Dsp::MorseKeyer` | `src/dsp/MorseKeyer.{h,cpp}` |
| `MorseTable[]` | `VCL/MorseTbl.pas` | `Dsp::MorseTable` | `src/dsp/MorseTable.{h,cpp}` |
| `BlackmanHarrisStepResponse` | `VCL/MorseKey.pas` | `Dsp::blackmanHarrisStep` | `src/dsp/BlackmanHarris.{h,cpp}` |
| `TMovingAverage` | `VCL/MovAvg.pas` | `Dsp::MovingAverage` | `src/dsp/MovingAverage.{h,cpp}` |
| Filt/Filt2 swap | `Contest.pas` (`SwapFilters`) | `Dsp::PingPongFilter` | `src/dsp/PingPongFilter.{h,cpp}` |
| `TModulator` | `VCL/Mixers.pas` | `Dsp::Modulator` | `src/dsp/Modulator.{h,cpp}` |
| `TVolumeControl` (AGC) | `VCL/VolumCtl.pas` | `Dsp::Agc` | `src/dsp/Agc.{h,cpp}` |
| `TQsb` (Rayleigh fading) | `Qsb.pas` | `Dsp::Qsb` | `src/dsp/Qsb.{h,cpp}` |
| `TQuickAverage` | `VCL/QuickAvg.pas` | `Dsp::QuickAverage` | `src/dsp/QuickAverage.{h,cpp}` |
| `TAlSoundOut` | `VCL/SndOut.pas` | `Audio::AudioEngine` | `src/audio/AudioEngine.{h,cpp}` |
| `TWaitThread.Synchronize`-bounce | `VCL/SndCustm.pas` | `Audio::SimulationWorker` (no Synchronize) | `src/audio/SimulationWorker.{h,cpp}` |
| `TAlWavFile` | `VCL/WavFile.pas` | `Audio::WavWriter` + `WavWriterThread` | `src/audio/WavWriter.{h,cpp}` |
| `LoadCallList` / `PickCall` | `CallLst.pas` | `Audio::CallsignDb` + `CallsignDbLoader` | `src/audio/CallsignDb.{h,cpp}` |
| `RndNormal`, `RndGaussLim`, `RndRayleigh`, `RndPoisson`, `RndUShaped` | `RndFunc.pas` | `Core::Random::*` | `src/core/Random.{h,cpp}` |
| `BlocksToSeconds`, `SecondsToBlocks` | `RndFunc.pas` | `Core::blocksToSeconds`, `Core::secondsToBlocks` | `src/core/Constants.h` (inline) |
| `TQso` / `QsoList` | `Log.pas` | `Scoring::Qso` / `Scoring::QsoLog` | `src/scoring/Qso.h` / `QsoLog.{h,cpp}` |
| `ExtractPrefix` | `Log.pas` | `Scoring::extractPrefix` | `src/scoring/ExtractPrefix.{h,cpp}` |
| `UpdateStats` / `UpdateStatsHst` | `Log.pas` | `Scoring::ScoreWpx` / `Scoring::ScoreHst` | `src/scoring/ScoreWpx.{h,cpp}` / `ScoreHst.{h,cpp}` |
| `LastQsoToScreen` row format | `Log.pas` | `Scoring::ScoreFormatter::format` | `src/scoring/ScoreFormatter.{h,cpp}` |
| `CalculateCRC32` | `VCL/Crc32.pas` | `Scoring::crc32` | `src/scoring/Crc32.{h,cpp}` |
| `FromIni` / `ToIni` | `Ini.pas` | `Persistence::Settings::load` / `save` | `src/persistence/Settings.{h,cpp}` |
| `TMainForm` (.dfm + .pas) | `Main.dfm` / `Main.pas` | `Ui::MainWindow` | `src/ui/MainWindow.{h,cpp}` |
| `TScoreDialog` | `ScoreDlg.dfm` / `ScoreDlg.pas` | `Ui::ScoreDialog` | `src/ui/dialogs/ScoreDialog.{h,cpp}` |
| `TVolumeSlider` | `VCL/VolmSldr.pas` | `Ui::VolumeSlider` | `src/ui/widgets/VolumeSlider.{h,cpp}` |
| `PaintBox1` histogram | `Main.pas::PaintHisto` | `Ui::HistogramPanel` | `src/ui/panels/HistogramPanel.{h,cpp}` |
| `Panel8`+`Shape2` (RIT) | Main.dfm | `Ui::RitSlider` | `src/ui/widgets/RitSlider.{h,cpp}` |

(Rows are added as code lands. Pascal line numbers are intentionally
omitted from this table because they drift; `git grep` in the parent repo
finds the symbol reliably.)
