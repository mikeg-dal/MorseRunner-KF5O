# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Phase D: MainWindow + panels matching Main.dfm pixel-for-pixel.
# D.G1 added menus; D.G2 adds panels/RightPanel; D.G3-G5 add the
# bottom panel, custom widgets, log area, and dialogs.
add_library(mr_ui STATIC
    MainWindow.cpp
    MainWindow.h
    panels/BottomPanel.cpp
    panels/BottomPanel.h
    panels/RightPanel.cpp
    panels/RightPanel.h
    dialogs/AboutDialog.cpp
    dialogs/AboutDialog.h
    dialogs/ScoreDialog.cpp
    dialogs/ScoreDialog.h
    widgets/HistogramPanel.cpp
    widgets/HistogramPanel.h
    widgets/LogView.cpp
    widgets/LogView.h
    widgets/RitSlider.cpp
    widgets/RitSlider.h
    widgets/VolumeSlider.cpp
    widgets/VolumeSlider.h
)
target_include_directories(mr_ui PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(mr_ui PUBLIC
    mr_core mr_audio mr_simulation mr_persistence mr_scoring
    Qt6::Core Qt6::Gui Qt6::Widgets)
set_target_properties(mr_ui PROPERTIES AUTOMOC ON)
morserunner_apply_warnings(mr_ui)
