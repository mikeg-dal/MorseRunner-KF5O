# Parity checklist

Every widget and behaviour of Morse Runner 1.68 (Main.dfm, Main.pas,
Log.pas, Ini.pas) against the Swift/AppKit app. Rows marked "Swift app"
describe where it deliberately differs.

Status legend: ◯ pending, ◔ in progress, ● done, ◑ accepted platform delta.

## Window

| Element | Expected (from Main.dfm) | Status |
|---|---|---|
| ClientWidth × ClientHeight | 700 × 413 fixed | ◯ |
| BorderStyle | bsSingle, biSystemMenu only | ◯ |
| Position | Centered on desktop | ◯ |
| Caption | "Morse Runner" (+ ":  <Name>" from INI) | ◯ |
| KeyPreview | True (form-level shortcut handling) | ◯ |
| Default font | MS Sans Serif 11 px → macOS system font 11 pt (Delphi Font.Height px = pt on macOS) | ◑ |

## Right panel (Panel9, alRight 212×284)

### GroupBox1 "Station"
| Control | Expected | Status |
|---|---|---|
| Edit4 (Call) | uppercase, default "VE3NEA", no key filter, no MaxLength (as Main.dfm); engine / Ini get the trimmed text | ● |
| CheckBox1 (QSK) | default checked | ◯ |
| SpinEdit1 (WPM) | range 10..120, default 30. Swift app: typed text is applied once it is a value in range (TSpinEdit hands unclamped text to OnChange), clamped on exit | ◑ |
| ComboBox1 (Pitch) | 300..900 Hz step 50, 13 items, default 600 Hz (idx 6) | ◯ |
| ComboBox2 (RX BW) | 100..600 Hz step 50, 11 items, default 500 Hz (idx 8) | ◯ |
| ComboBox1/2 width | Main.dfm 65 px; a small NSPopUpButton needs 78 px to show "900 Hz" untruncated, so both are 78 px | ◑ |
| VolumeSlider1 (Mon Level) | value 0.75 ≡ −15 dB; every drag / menu / double-click goes through VolumeSlider1Change's `Db := 80*(Value−0.75)` remap (DbScale 60), hint '%.0f dB' ("-0 dB" as Delphi prints it); FromIni sets Value without the remap. Swift app persists the level on every change (Ini SelfMonVolume) | ● |
| VolumeSlider1 drawing | VolmSldr.pas Paint geometry pixel for pixel; the wedge body is filled light grey because its white edges vanish on the lighter macOS group box (Windows drew it on grey clBtnFace) | ◑ |

### GroupBox3 "Band Conditions"
| Control | Expected | Status |
|---|---|---|
| CheckBox4 (QRN) | default checked | ◯ |
| CheckBox3 (QRM) | default checked | ◯ |
| CheckBox2 (QSB) | default checked | ◯ |
| CheckBox5 (Flutter) | default checked | ◯ |
| CheckBox6 (LIDS) | default checked | ◯ |
| SpinEdit3 (Activity) | range 1..9, default 3 | ◯ |

### Panel10 (Duration + Run)
| Control | Expected | Status |
|---|---|---|
| SpinEdit2 (Duration) | range 1..240, default 30. Main.dfm MaxLength 2 cannot hold 120/240; Swift app allows 3 digits | ◑ |
| ToolBar1 / ToolButton1 (Run) | dropdown menu with PopupMenu1 items; body toggles Pile-Up ↔ Stop, caption reads "Stop" while running (ToolButton1Click) | ◯ |

## Bottom panel (Panel1, alBottom 700×119)

| Element | Expected | Status |
|---|---|---|
| Edit1 (Call) | Bold MS Sans 16pt, MaxLen 12, [A-Za-z0-9/?]; a keystroke at MaxLength is refused (not truncated); Edit1Enter selects the '?' (Pos > 1) on every focus change. Swift app: a paste is filtered and cut to the room left (VCL pastes bypass OnKeyPress); AutoSelect off puts the caret at the end | ◑ |
| Edit2 (RST) | Bold 16pt, MaxLen 3, [0-9]; Edit2Enter selects the middle digit of a 3-digit RST; Swift app also accepts cut numbers T/O→0, N→9 (deviation) | ◑ |
| Edit3 (NR) | Bold 16pt, MaxLen 4, [0-9]; Swift app also accepts cut numbers T/O→0, N→9 (deviation) | ◑ |
| SpeedButton4..11 | F1..F8 captions, send Tag-mapped messages | ◯ |
| Panel2 (Clock) | Arial 24pt, black bg, "00:00:00" | ◯ |
| Panel4 (Mode) | bold red, "Pile-Up"/"Single Calls"/"COMPETITION"/"H S T", empty when stopped. Port uses 11 pt; the 21 pt noted earlier does not fit the 26-px panel — unverified against Main.dfm | ◯ |
| Panel7 (Rate) | "N qso/hr." | ◯ |
| Panel3 + PaintBox1 (Histogram) | 48 bins × 5 min, clInfoBk bg, clGreen 4-px stride bars | ◯ |
| Panel8 + Shape2 (RIT) | orange indicator, Width=BW/9, Left=((PW−W)/2)+Rit/9 | ◯ |
| RIT mouse | v1.68: click left/right of the marker ∓50 Hz, click the marker → 0 (Panel8/Shape2MouseDown). Swift app adds dragging the marker: 9 Hz per px from the grab point, snapped to 50 Hz, ±500; a click without movement still resets (on mouse-up) (deviation) | ◑ |
| Panel11 + ListView1 (ScoreTable) | 3 rows ("Pts","Mult","Score") × 3 cols ("", "Raw", "Verified"); Log.Clear resets cells ('' / '0'). Pascal leaves Panel11's HST caption at the previous run's score until the first QSO; Swift app resets it to "0" at Run | ◑ |

## Log area (Panel6, alClient)

| Element | Expected | Status |
|---|---|---|
| Shape1 background | clBg #E9FCFE | ◯ |
| Logo (3 layered Arial 35pt Bold Italic) | green/aqua/#5C9CBC offset 1px | ◯ |
| Copyright + FREEWARE labels | clBlue underline header, clRed last 3 chars | ◯ |
| Port credit | Swift app adds "Ported to macOS by Mike, KF5O" below FREEWARE, centred under the copyright line (addition) | ◑ |
| RichEdit1 → LogView | Menlo 13pt, header underline+blue, row format `' hh:nn:ss  %-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s'` | ◯ |
| QSO time (Log.SaveQso `Qso.T := BlocksToSeconds(Tst.BlockNumber)`) | Swift app: taken on the sim thread from the block counter when the save is processed (not from the 30 Hz GUI poll) | ● |
| View Score Table during a run | Pascal allows it; the next DataToLastQso's `Lines.Delete(Count-1)` then deletes a score-list line. Swift app only replaces a QSO row it appended itself (otherwise appends) | ◑ |
| Clock / rate / pile-up captions | updated by the GUI poll in all run-loop modes (keeps ticking while a menu or dialog is open) | ● |
| End of contest | HST always (even when stopped by the user): HstResults.txt line `yyyy-mm-dd hh:nn<TAB>Call<TAB>Name<TAB>Score` + 'HST Score: N'; WPX only when time runs out: CRC-stamped score-list line, HiScore, record banner; others nothing. Dates are local wall-clock, Gregorian, locale-independent; the call is the trimmed Edit4 text | ● |

## Menus

| Menu | Items | Status |
|---|---|---|
| File | View Score Table, View Hi-Score web page…, ─, Audio Recording Enabled (toggle), Play Recorded Audio (initially disabled), ─, Exit | ◯ |
| Run | Pile-Up (F8), Single Calls, WPX Competition, HST Competition (Ctrl+F8), ─, Stop (initially disabled). F8 is on both Pile-Up and Send › NIL in the shipped form; Swift app gives it to Pile-Up while stopped and to NIL during a run (Pile-Up is disabled then). WPX/HST force conditions / duration (HST: activity 4, 600 Hz) through the controls, so they are saved as ToIni would | ◑ |
| Send | CQ (F1), Number (F2), TU (F3), My Call (F4), His Call (F5), QSO B4 (F6), `<?>` (F7), NIL (F8) | ◯ |
| Settings | Call…, QSK, CW Speed 10..60 step 5, CW Pitch 300..900 step 50, CW Bandwidth 100..600 step 50, Mon Level −60/−40/−20/0/+20 dB, ─, QRN/QRM/QSB/Flutter/LIDS toggles, Activity 1..9, ─, Duration 5/10/15/30/60/90/120, HST Operator…; value submenus are exclusive radio groups whose check mark mirrors the right-panel control (no check when the control holds an unlisted value) | ◯ |
| Help | Web Page…, Readme…, ─, About… (Swift app opens the dxatlas.com pages over https) | ◑ |
| macOS additions | Application menu (About, Hide ⌘H, Hide Others, Show All, Quit), Edit (Undo/Redo/Cut/Copy/Paste/Select All for the text fields), Window (Minimize, Bring All to Front) | ◑ |
| PopupMenu1 | Pile-Up (default), Single Calls, WPX Competition, HST Competition, ─, Stop | ◯ |

## Keyboard shortcuts

| Key | Action | Status |
|---|---|---|
| F1–F8 | send respective message | ◯ |
| `\` | send CQ (alias of F1) | ◯ |
| Esc | abort send | ◯ |
| `;`, Insert | send HisCall then NR | ◯ |
| `.`, `,`, `+`, `[` | TU then SaveQso | ◯ |
| Space | focus round-robin (Edit1 ↔ Edit3, Edit2 auto-"599") | ◯ |
| Tab, Shift-Tab | native field nav | ◯ |
| Alt-W, Ctrl-W, F11 | WipeBoxes (matched on the character, any keyboard layout) | ● |
| Alt-Enter, Shift-Enter, Ctrl-Enter | force SaveQso | ◯ |
| Command = Ctrl | Swift app: Pascal's Ctrl combinations also answer to Command (macOS reserves Control-Up etc.): ⌘W, ⌘Return, ⌘Up/Down, ⌘F9/F10; other ⌘ keys go to the menus | ◑ |
| Up / Down | ±50 Hz RIT | ◯ |
| Ctrl-Up / Ctrl-Down | bandwidth ± step | ◯ |
| PgUp / PgDn | ±5 WPM (round) | ◯ |
| Ctrl-F9 / Ctrl-F10, Alt-F9 / Alt-F10 | ±5 WPM (round); a bare F9 / F10 is swallowed (FormKeyDown Key := 0) | ◯ |
