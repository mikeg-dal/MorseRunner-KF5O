# Architecture

Morse Runner (macOS port) is organized as a layered Qt 6 application:

```
+------------------------------------------+
| mr_app    (AppController, main wiring)   |
+------------------------------------------+
| mr_ui     (MainWindow, widgets, dialogs) |
+------------------------------------------+
| mr_audio  (AudioEngine, SPSC ring, WAV)  |
| mr_simulation (Contest, Station, DxOper) |
| mr_scoring    (QsoLog, prefix, CRC32)    |
+------------------------------------------+
| mr_dsp    (MorseKeyer, MovAvg, Mod, AGC) |
| mr_persistence (Settings + INI migration)|
+------------------------------------------+
| mr_core   (Constants, Theme, Random, ..) |
| mr_util   (PlatformPaths, UrlOpener)     |
+------------------------------------------+
| Qt 6 (Core/Gui/Widgets/Multimedia)       |
| macOS frameworks (CoreAudio, Foundation) |
+------------------------------------------+
```

## Threads

Five threads, all named via `pthread_setname_np` for Instruments:

| Thread       | Owns                                | Priority        |
|--------------|-------------------------------------|-----------------|
| `mr-main`    | Qt event loop, all widgets, settings| Default         |
| `mr-sim`     | Contest, Station, DxOperator        | High            |
| `mr-audio`   | QAudioSink + its QIODevice           | TimeCritical    |
| `mr-wav`     | WavWriterThread                      | Low             |
| `mr-dbload`  | CallsignDbLoader (one-shot)          | Normal          |

## Hand-offs

- **Sim → Audio**: `SpscRingBuffer<AudioFrame, 8>`; audio thread never
  blocks (writes silence + `underrunCount++` on empty); sim thread waits
  on a `std::condition_variable` when ring full.
- **Sim → WAV**: `SpscRingBuffer<WavFrame, 64>`; drop-oldest on full.
- **Sim → GUI**: thread-safe `GuiUpdateQueue` (latest-wins scalars +
  256-row bounded log FIFO), drained by a 30 Hz `QTimer` on the GUI thread.
- **GUI → Sim (settings)**: `std::atomic<std::shared_ptr<const SettingsSnapshot>>`,
  read once per block at the top of `renderNextBlock`. RCU-style; the
  hot path never locks.
- **GUI → Sim (commands)**: `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`.

## Why no `Synchronize`

The original Delphi code drives `TContest.GetAudio` from a Windows
multimedia worker thread that calls `Synchronize(ProcessEvent)`, bouncing
every audio buffer back to the GUI thread before rendering it. The GUI
thread therefore handles both painting *and* DSP — under high pile-up
load the UI freezes audibly. The port eliminates this entirely: the GUI
thread sees only paint events and small queued updates; the DSP runs in
its own thread; audio I/O is its own real-time-safe thread.

(Full thread diagram and class breakdown will be expanded as Phases B–E
land their implementations.)
