# Parity checklist

Status legend: ◯ pending, ◔ in progress, ● done, ◑ accepted platform delta.

## Window

| Element | Expected (from Main.dfm) | Status |
|---|---|---|
| ClientWidth × ClientHeight | 700 × 413 fixed | ◯ |
| BorderStyle | bsSingle, biSystemMenu only | ◯ |
| Position | Centered on desktop | ◯ |
| Caption | "Morse Runner" (+ ":  <Name>" from INI) | ◯ |
| KeyPreview | True (form-level shortcut handling) | ◯ |
| Default font | MS Sans Serif 11pt → Helvetica 11pt | ◑ |

## Right panel (Panel9, alRight 212×284)

### GroupBox1 "Station"
| Control | Expected | Status |
|---|---|---|
| Edit4 (Call) | uppercase, MaxLen 12, default "VE3NEA" | ◯ |
| CheckBox1 (QSK) | default checked | ◯ |
| SpinEdit1 (WPM) | range 10..120, default 30 | ◯ |
| ComboBox1 (Pitch) | 300..900 Hz step 50, 13 items, default 600 Hz (idx 6) | ◯ |
| ComboBox2 (RX BW) | 100..600 Hz step 50, 11 items, default 500 Hz (idx 8) | ◯ |
| VolumeSlider1 (Mon Level) | value 0.75 ≡ −15 dB | ◯ |

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
| SpinEdit2 (Duration) | range 1..240, default 30 | ◯ |
| ToolBar1 / ToolButton1 (Run) | dropdown menu with PopupMenu1 items; body toggles Pile-Up ↔ Stop, caption reads "Stop" while running (ToolButton1Click) | ◯ |

## Bottom panel (Panel1, alBottom 700×119)

| Element | Expected | Status |
|---|---|---|
| Edit1 (Call) | Bold MS Sans 16pt, MaxLen 12, [A-Za-z0-9/?] | ◯ |
| Edit2 (RST) | Bold 16pt, MaxLen 3, [0-9] | ◯ |
| Edit3 (NR) | Bold 16pt, MaxLen 4, [0-9] | ◯ |
| SpeedButton4..11 | F1..F8 captions, send Tag-mapped messages | ◯ |
| Panel2 (Clock) | Arial 24pt, black bg, "00:00:00" | ◯ |
| Panel4 (Mode) | bold red, "Pile-Up"/"Single Calls"/"COMPETITION"/"H S T", empty when stopped. Port uses 11 pt; the 21 pt noted earlier does not fit the 26-px panel — unverified against Main.dfm | ◯ |
| Panel7 (Rate) | "N qso/hr." | ◯ |
| Panel3 + PaintBox1 (Histogram) | 48 bins × 5 min, clInfoBk bg, clGreen 4-px stride bars | ◯ |
| Panel8 + Shape2 (RIT) | orange indicator, Width=BW/9, Left=((PW−W)/2)+Rit/9 | ◯ |
| Panel11 + ListView1 (ScoreTable) | 3 rows ("Pts","Mult","Score") × 3 cols ("", "Raw", "Verified") | ◯ |

## Log area (Panel6, alClient)

| Element | Expected | Status |
|---|---|---|
| Shape1 background | clBg #E9FCFE | ◯ |
| Logo (3 layered Arial 35pt Bold Italic) | green/aqua/#5C9CBC offset 1px | ◯ |
| Copyright + FREEWARE labels | clBlue underline header, clRed last 3 chars | ◯ |
| RichEdit1 → LogView | Menlo 13pt, header underline+blue, row format `' hh:nn:ss  %-12s  %.3d %.4d  %.3d %.4d  %-5s  %-3s'` | ◯ |

## Menus

| Menu | Items | Status |
|---|---|---|
| File | View Score Table, View Hi-Score web page…, ─, Audio Recording Enabled (toggle), Play Recorded Audio (initially disabled), ─, Exit | ◯ |
| Run | Pile-Up (Pascal F8 — dropped: collides with Send › NIL F8, which keeps it; Run button body starts Pile-Up), Single Calls, WPX Competition, HST Competition (Ctrl+F8), ─, Stop (initially disabled) | ◯ |
| Send | CQ (F1), Number (F2), TU (F3), My Call (F4), His Call (F5), QSO B4 (F6), `<?>` (F7), NIL (F8) | ◯ |
| Settings | Call…, QSK, CW Speed 10..60 step 5, CW Pitch 300..900 step 50, CW Bandwidth 100..600 step 50, Mon Level −60/−40/−20/0/+20 dB, ─, QRN/QRM/QSB/Flutter/LIDS toggles, Activity 1..9, ─, Duration 5/10/15/30/60/90/120, HST Operator…; value submenus are exclusive radio groups whose check mark mirrors the right-panel control (no check when the control holds an unlisted value) | ◯ |
| Help | Web Page…, Readme…, ─, About… | ◯ |
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
| Alt-W, Ctrl-W, F11 | WipeBoxes | ◯ |
| Alt-Enter, Shift-Enter, Ctrl-Enter | force SaveQso | ◯ |
| Up / Down | ±50 Hz RIT | ◯ |
| Ctrl-Up / Ctrl-Down | bandwidth ± step | ◯ |
| PgUp / PgDn | ±5 WPM (round) | ◯ |
| Ctrl-F9 / Ctrl-F10, Alt-F9 / Alt-F10 | ±5 WPM (round) | ◯ |
