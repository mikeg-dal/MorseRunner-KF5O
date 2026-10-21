// Morse Runner — native Swift port
// Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
// Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// VolumeSlider1 (VCL/VolmSldr.pas TVolumeSlider, DbMax 0, DbScale 60)
// and the Main.pas handlers around it. Value is 0…1; the contest's
// self-monitor gain is 10^((Value − 0.75)·4) of that same Value.
//
// TMainForm.VolumeSlider1Change writes the slider's Db property:
//   Db := 80 * (Value - 0.75)        → SetDb: Value := Db/DbScale + 1
// so every drag step, Mon. Level menu pick and double-click lands on
// Value' = 80·(Value − 0.75)/60 + 1 (clamped). Reproduced as shipped.

import Foundation
import MRCore

public enum MonitorLevel {
    public static let dbMax: Float = 0
    public static let dbScale: Float = 60
    /// TVolumeSlider default and VolumeSliderDblClick.
    public static let defaultValue: Float = 0.75
    /// TVolumeSlider Margin (FMargin) and VMargin.
    public static let margin = 5
    public static let vMargin = 6

    /// TVolumeSlider.SetValue: Max(0, Min(1, Value)). NaN → 0.
    public static func clamp(_ v: Float) -> Float {
        v.isNaN ? 0 : max(0, min(1, v))
    }

    /// GetDb: DbMax + (Value − 1)·DbScale.
    public static func db(value: Float) -> Float {
        dbMax + (value - 1) * dbScale
    }

    /// SetDb: Value := (dB − DbMax)/DbScale + 1, through SetValue.
    public static func value(db: Float) -> Float {
        clamp((db - dbMax) / dbScale + 1)
    }

    /// TMainForm.VolumeSlider1Change applied to the slider's Value.
    public static func afterMainFormChange(_ value: Float) -> Float {
        Self.value(db: 80 * (value - 0.75))
    }

    /// SelfMonClick: Value := Tag/80 + 0.75 (SetValue), then OnChange.
    public static func menuValue(tag: Int) -> Float {
        afterMainFormChange(clamp(Float(tag) / 80 + 0.75))
    }

    /// VolumeSliderDblClick: Value := 0.75, then OnChange.
    public static var doubleClickValue: Float { afterMainFormChange(defaultValue) }

    /// MouseMove while dragging: Value := DownValue + (X − DownX)/(Width −
    /// 2·Margin) (SetValue), then OnChange.
    public static func dragValue(downValue: Float, deltaX: Double, width: Double) -> Float {
        let span = width - Double(2 * margin)
        guard span > 0 else { return afterMainFormChange(clamp(downValue)) }
        return afterMainFormChange(clamp(downValue + Float(deltaX / span)))
    }

    /// TVolumeSlider.UpdateHint: Format('%.1f dB', [Db]). Shown after
    /// FromIni, which sets Value without OnChange.
    public static func sliderHint(value: Float) -> String {
        String(format: "%.1f dB", Double(db(value: value)))
    }

    /// VolumeSlider1Change's hint: '+%.0f dB' when positive, else
    /// '%.0f dB'. Delphi's Format prints "-0" for −0.4 just as printf
    /// does, so no special case.
    public static func mainFormHint(value: Float) -> String {
        let d = db(value: value)
        return d > 0 ? String(format: "+%.0f dB", Double(d)) : String(format: "%.0f dB", Double(d))
    }

    /// Ini.pas ToIni: Round(80·(Value − 0.75)), the Pascal INI integer.
    public static func iniInteger(value: Float) -> Int {
        delphiRound(Double(80 * (value - 0.75)))
    }

    /// ThumbRect's centre: Margin + Round((Width − 2·Margin)·Value).
    public static func thumbCenterX(value: Float, width: Int) -> Int {
        margin + delphiRound(Double(Float(width - 2 * margin) * value))
    }

    /// ThumbRect: Rect(x − 4, VMargin div 2, x + 5, Height − VMargin div
    /// 2 + 1), right/bottom exclusive. (x, y, width, height).
    public static func thumbRect(value: Float, width: Int, height: Int)
        -> (x: Int, y: Int, width: Int, height: Int) {
        let x = thumbCenterX(value: value, width: width)
        let top = vMargin / 2
        return (x - 4, top, 9, (height - vMargin / 2 + 1) - top)
    }

    /// PtInRect(ThumbRect, P): only a press on the thumb starts a drag.
    public static func hitsThumb(x: Int, y: Int, value: Float, width: Int, height: Int) -> Bool {
        let r = thumbRect(value: value, width: width, height: height)
        return x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height
    }
}
