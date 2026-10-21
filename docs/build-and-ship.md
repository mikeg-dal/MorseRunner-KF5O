# Build and ship runbook

## Prerequisites

- macOS 15 or later.
- Xcode 26 or later (Swift 6.2).
- xcodegen: `brew install xcodegen`.
- For regenerating the reference data only: CMake 3.28+, Ninja and Qt 6
  (`brew install cmake ninja qt`).

## Build and test

```sh
cd Swift
swift test                       # engine + app logic, all modules
swift test -c release            # same, optimized
swift test --sanitize=thread --filter 'MRAudioTests|MRSimulationTests'

xcodegen generate                # writes MorseRunner.xcodeproj (not committed)
xcodebuild -project MorseRunner.xcodeproj -scheme MorseRunner \
    -derivedDataPath .build-app build
xcodebuild -project MorseRunner.xcodeproj -scheme MorseRunner \
    -derivedDataPath .build-app test      # adds the app-hosted tests
open .build-app/Build/Products/Debug/MorseRunner.app
```

The app's entitlements file is `resources/MorseRunner.entitlements`
(hardened runtime, no sandbox). `project.yml` references it through
`CODE_SIGN_ENTITLEMENTS` so xcodegen never rewrites it.

## Reference data

The Swift engine is checked against data produced by the C++ engine in
`src/`. Regenerate it only when the C++ reference changes:

```sh
tools/golden/regenerate.sh            # all modules
tools/golden/regenerate.sh dsp        # one module
```

The script configures CMake with `-DMORSERUNNER_BUILD_GOLDEN=ON` and
`-ffp-contract=off` (Swift never fuses multiply-adds), builds the dump
tools, and writes into `Swift/Sources/MRTestSupport/Fixtures`. It finds
Qt through `QT_ROOT`, the `build/arm64-release` cache, or Homebrew.

## Release

One-time setup:

1. Import your Developer ID Application certificate into the login
   keychain.
2. Store notarization credentials in the keychain:
   ```sh
   xcrun notarytool store-credentials <profile> \
       --key /path/to/AuthKey_XXXXXXXXXX.p8 \
       --key-id XXXXXXXXXX \
       --issuer <issuer-uuid-from-App-Store-Connect>
   ```

Each release:

```sh
export MR_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
export MR_TEAM_ID=<TEAMID>
export MR_NOTARY_PROFILE=<profile>
scripts/release_swift.sh
```

The script builds a universal (arm64 + x86_64) Release app with the
hardened runtime and secure timestamps, refuses to continue if the
`get-task-allow` entitlement is present, notarizes, staples, checks
Gatekeeper, and writes `dist/MorseRunner-<version>-macOS.zip`. Upload the
zip to a GitHub Release; `dist/` is not committed.

The version comes from `MARKETING_VERSION` in `Swift/project.yml`.

## Icon

```sh
./scripts/make_iconset.sh resources/icons/MorseRunner.svg   # needs `brew install librsvg`
```

`MorseRunner.svg` is the vector master, a macOS-style redraw of the
original `MorseRun.ico` (stopwatch and straight key). It produces
`resources/icons/MorseRunner.icns`, which both apps use.

## The C++/Qt reference port

The C++/Qt app in `src/` can still be built, for comparing behaviour:

```sh
cmake --preset arm64-release
cmake --build --preset arm64-release --parallel
ctest --test-dir build/arm64-release --output-on-failure
```

Its old distribution scripts (`scripts/build.sh`, `sign_and_notarize.sh`,
`make_dmg.sh`, `verify_bundle.sh`) apply to that app only. If you ever
ship it, `sign_and_notarize.sh` must re-sign every Qt plug-in: Qt's
plug-ins are signed by another team and library validation rejects them
otherwise.
