# Pascal → Swift symbol mapping

Where each part of Morse Runner 1.68 lives in the Swift port. Paths are
under `Swift/`. Pascal line numbers are left out on purpose because they
drift; search the Pascal source (https://github.com/VE3NEA/MorseRunner)
for the symbol.

| Pascal symbol | Pascal file | Swift symbol | Swift file |
|---|---|---|---|
| `TContest` / `Tst` | `Contest.pas` | `Contest` | `Sources/MRSimulation/Contest.swift` |
| `TContest.GetAudio` | `Contest.pas` | `Contest.renderNextBlock(into:)` | `Sources/MRSimulation/Contest.swift` |
| `TStation` (base) | `Station.pas` | `Station` | `Sources/MRSimulation/Station.swift` |
| `TMyStation` | `MyStn.pas` | `MyStation` | `Sources/MRSimulation/MyStation.swift` |
| `TDxStation` | `DxStn.pas` | `DxStation` | `Sources/MRSimulation/DxStation.swift` |
| `TDxOperator` (state machine) | `DxOper.pas` | `DxOperator`, `OperatorState` | `Sources/MRSimulation/DxOperator.swift` |
| `IsMyCall` | `DxOper.pas` | `isMyCall` | `Sources/MRSimulation/IsMyCall.swift` |
| `TQrnStation` / `TQrmStation` | `QrnStn.pas` / `QrmStn.pas` | `QrnStation` / `QrmStation` | `Sources/MRSimulation/QrnStation.swift`, `QrmStation.swift` |
| `TStations` | `StnColl.pas` | `StationCollection` | `Sources/MRSimulation/StationCollection.swift` |
| `TStationMessage`, message sets | `Station.pas` | `Message`, `MessageSet` | `Sources/MRSimulation/Messages.swift` |
| `NrAsText` | `Station.pas` | `nrAsText` | `Sources/MRSimulation/NumberFormat.swift` |
| `TRunMode` | `Ini.pas` | `RunMode` | `Sources/MRSimulation/Engine.swift` |
| `LoadCallList` / `PickCall` | `CallLst.pas` | `CallsignDb` | `Sources/MRSimulation/CallsignDb.swift` |
| `TKeyer` | `VCL/MorseKey.pas` | `MorseKeyer` | `Sources/MRDSP/MorseKeyer.swift` |
| `MorseTable[]` | `VCL/MorseTbl.pas` | `MorseTable`, `encodeMessage` | `Sources/MRDSP/MorseTable.swift` |
| `BlackmanHarrisStepResponse` | `VCL/MorseKey.pas` | `blackmanHarrisStep` | `Sources/MRDSP/BlackmanHarris.swift` |
| `TMovingAverage` | `VCL/MovAvg.pas` | `MovingAverage` | `Sources/MRDSP/MovingAverage.swift` |
| `Filt`/`Filt2` + `SwapFilters` | `Contest.pas` | `PingPongFilter` | `Sources/MRDSP/PingPongFilter.swift` |
| `TModulator` | `VCL/Mixers.pas` | `Modulator` | `Sources/MRDSP/Modulator.swift` |
| `TVolumeControl` (AGC) | `VCL/VolumCtl.pas` | `Agc` | `Sources/MRDSP/Agc.swift` |
| `TQsb` | `Qsb.pas` | `Qsb` | `Sources/MRDSP/Qsb.swift` |
| `TQuickAverage` | `VCL/QuickAvg.pas` | `QuickAverage` | `Sources/MRDSP/QuickAverage.swift` |
| `TReImArrays` | `VCL/SndTypes.pas` | `ComplexBuf` | `Sources/MRDSP/ComplexBuf.swift` |
| `RndNormal`, `RndGaussLim`, `RndRayleigh`, `RndPoisson`, `RndUShaped` | `RndFunc.pas` | `Random` | `Sources/MRCore/Random.swift` |
| `BlocksToSeconds`, `SecondsToBlocks` | `RndFunc.pas` | `AudioK.blocksToSeconds`, `AudioK.secondsToBlocks` | `Sources/MRCore/Constants.swift` |
| `Round` (banker's rounding) | Delphi RTL | `delphiRound` | `Sources/MRCore/DelphiRound.swift` |
| `TAlWavFile` | `VCL/WavFile.pas` | `WavWriter` | `Sources/MRCore/WavWriter.swift` |
| `TAlSoundOut` + `Synchronize` bounce | `VCL/SndOut.pas`, `VCL/SndCustm.pas` | `AudioOutput`, `SimulationThread`, `AudioBlockRing` (no GUI-thread DSP) | `Sources/MRAudio/` |
| `TQso`, `QsoList`, `SaveQso`, `CheckErr`, `UpdateStats(Hst)`, `ShowRate` | `Log.pas` | `Qso`, `QsoLog` | `Sources/MRScoring/QsoLog.swift` |
| `ExtractPrefix` | `Log.pas` | `extractPrefix` | `Sources/MRScoring/ExtractPrefix.swift` |
| `CallToScore` | `Log.pas` | `callToScore` | `Sources/MRScoring/CallToScore.swift` |
| `CalculateCRC32`, score line | `VCL/Crc32.pas`, `Main.pas` | `calculateCrc32(_:seed:)`, `stampScoreLine` | `Sources/MRScoring/Crc32.swift` |
| `FromIni` / `ToIni` | `Ini.pas` | `Settings`, `UserSettings` | `Sources/MRPersistence/Settings.swift` |
| `ProcessEnter`, `ProcessSpace`, `Advance`, `Edit1Change`, `WipeBoxes` | `Main.pas` | `OperatingState` | `Sources/MRAppCore/OperatingState.swift` |
| `Run` (control enabling, WPX/HST rules) | `Main.pas` | `RunModeRules` | `Sources/MRAppCore/RunModeRules.swift` |
| `FormKeyDown` / `FormKeyPress` | `Main.pas` | `KeyCommand` | `Sources/MRAppCore/KeyCommand.swift` |
| `Edit1/2/3KeyPress`, `MaxLength`, `CharCase` | `Main.pas`, `Main.dfm` | `EntryFilter` | `Sources/MRAppCore/EntryFilter.swift` |
| `IncRit`, `UpdateRitIndicator`, speed / pitch / bandwidth steps | `Main.pas` | `Rit`, `SpeedStep`, `PitchTable`, `BandwidthTable` | `Sources/MRAppCore/StationTables.swift` |
| `VolumeSlider1Change`, `SelfMonClick` | `Main.pas` | `MonitorLevel` | `Sources/MRAppCore/MonitorLevel.swift` |
| `PopupScoreWpx`, `PopupScoreHst` | `Main.pas` | `ContestEndPolicy`, `ScoreFiles` | `Sources/MRAppCore/ContestEnd.swift`, `ScoreFiles.swift` |
| `TMainForm` (layout, menus) | `Main.dfm` / `Main.pas` | `MainWindowController` (+Layout, +Menus, +Operating, +Files) | `App/Sources/` |
| `TScoreDialog` | `ScoreDlg.dfm` / `ScoreDlg.pas` | `ScoreDialog` | `App/Sources/Widgets/Dialogs.swift` |
| `TVolumeSlider` | `VCL/VolmSldr.pas` | `VolumeSlider` | `App/Sources/Widgets/CustomViews.swift` |
| `PaintHisto` | `Log.pas` | `HistogramView`, `HistogramGeometry` | `App/Sources/Widgets/CustomViews.swift`, `Sources/MRAppCore/Captions.swift` |
| `Panel8` + `Shape2` (RIT) | `Main.dfm` | `RitView` | `App/Sources/Widgets/CustomViews.swift` |
| `ListView1` score table | `Main.dfm` | `ScoreTableView`, `ScoreGridView` | `App/Sources/Widgets/ScoreTableView.swift` |
| `RichEdit1` log | `Main.dfm`, `Log.pas` | `LogView` | `App/Sources/Widgets/CustomViews.swift` |
