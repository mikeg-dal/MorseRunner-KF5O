# Morse Runner — macOS Qt 6 port
# Copyright (C) 2004-2006 Alex Shovkoplyas, VE3NEA (original Delphi)
# Copyright (C) 2026 Mike Garcia, KF5O (macOS port)
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Public knob: override the bundle identifier at configure time with
# -DMR_BUNDLE_ID=com.your-domain.morserunner. The default ties the app to
# the original port author's identifier and should be changed before
# distribution.
set(MR_BUNDLE_ID "com.garciamike1.morserunner"
    CACHE STRING "CFBundleIdentifier for the .app bundle")

# morserunner_configure_bundle(<target>)
#
# Substitutes the Info.plist template, attaches the .icns, marks the bundle
# as retina-aware, and copies Master.dta (if present) into Resources. The
# Info.plist is the single source of truth for end-user metadata — keep
# CFBundleShortVersionString and CFBundleVersion synchronized with the
# project() VERSION declared in the top-level CMakeLists.txt.
function(morserunner_configure_bundle target)
    set(plist_in  "${CMAKE_SOURCE_DIR}/resources/Info.plist.in")
    set(plist_out "${CMAKE_CURRENT_BINARY_DIR}/Info.plist")
    configure_file("${plist_in}" "${plist_out}" @ONLY)

    set_target_properties(${target} PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST            "${plist_out}"
        MACOSX_BUNDLE_BUNDLE_NAME           "MorseRunner"
        MACOSX_BUNDLE_BUNDLE_VERSION        "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING  "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}"
        MACOSX_BUNDLE_GUI_IDENTIFIER        "${MR_BUNDLE_ID}"
        MACOSX_BUNDLE_ICON_FILE             "MorseRunner.icns"
        MACOSX_BUNDLE_COPYRIGHT
            "(C) 2004-2006 Alex Shovkoplyas, VE3NEA. macOS port (C) 2026 Mike Garcia. MPL 2.0."
    )

    # Icon: optional in Phase A — the iconset has not been produced yet.
    set(icns "${CMAKE_SOURCE_DIR}/resources/icons/MorseRunner.icns")
    if(EXISTS "${icns}")
        target_sources(${target} PRIVATE "${icns}")
        set_source_files_properties("${icns}" PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources")
    endif()

    # Master.dta: optional. The CallsignDb falls back to a single
    # hardcoded callsign ("P29SX") when the file is absent, matching the
    # original Delphi behavior.
    set(master_dta "${CMAKE_SOURCE_DIR}/resources/data/Master.dta")
    if(EXISTS "${master_dta}")
        target_sources(${target} PRIVATE "${master_dta}")
        set_source_files_properties("${master_dta}" PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources/data")
    endif()

    # Readme.txt: bundled so the in-app "Help > Readme..." menu item can
    # display it without a network round-trip.
    set(readme "${CMAKE_SOURCE_DIR}/resources/docs/Readme.txt")
    if(EXISTS "${readme}")
        target_sources(${target} PRIVATE "${readme}")
        set_source_files_properties("${readme}" PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources/docs")
    endif()
endfunction()
