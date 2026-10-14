# Build and ship runbook

## Prerequisites

- macOS 12.0 (Monterey) or newer (development host).
- Xcode command-line tools: `xcode-select --install`.
- CMake 3.28+: `brew install cmake`.
- Ninja: `brew install ninja`.
- Qt 6.10+: `brew install qt` *or* install Qt online installer and export
  `QT_ROOT=/path/to/Qt/6.10.0/macos`.

## One-time bootstrap

```sh
cd macos-qt
./scripts/bootstrap_resources.sh
```

This copies the MPL `LICENSE`, end-user `Readme.txt`, and (if available)
the binary `Master.dta` callsign database from the parent Delphi repo
into `resources/`. After this step the directory is self-contained.

## Local build

```sh
./scripts/build.sh                    # Release (arm64)
./scripts/build.sh --debug            # Debug
./scripts/build.sh --tsan             # Debug + ThreadSanitizer
./scripts/build.sh --asan             # Debug + AddressSanitizer
```

Output: `build/<preset>/MorseRunner.app`.

## Run unit tests

```sh
ctest --preset arm64-debug
```

## Code signing (developer iteration)

If `MR_SIGN_IDENTITY` is exported, the CMake build performs an ad-hoc
sign so the bundle launches under the hardened runtime locally. This is
not a notarized distribution signing — see the next section.

```sh
export MR_SIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAMID>)"
./scripts/build.sh
```

## Distribution signing & notarization

```sh
# One-time keychain seed (interactive):
xcrun notarytool store-credentials notary-mr \
    --apple-id you@example.com \
    --team-id TEAMIDXXXX \
    --password <app-specific-password>

# Each release:
export MR_SIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAMID>)"
export MR_NOTARY_PROFILE="notary-mr"
./scripts/build.sh
./scripts/sign_and_notarize.sh
./scripts/make_dmg.sh
./scripts/verify_bundle.sh
```

After `make_dmg.sh` the distributable artifact is:

```
build/arm64-release/MorseRunner-<version>.dmg
```

stapled with a notarization ticket; Gatekeeper accepts it offline.

## Iconset regeneration

```sh
./scripts/make_iconset.sh resources/icons/MorseRunner.svg   # needs `brew install librsvg`
```

`MorseRunner.svg` is the vector master — a macOS-style redraw of the
original `MorseRun.ico` motif (stopwatch + straight key). A 1024×1024 PNG
is also accepted and downscaled with `sips`.

Produces `resources/icons/MorseRunner.icns`. The `.iconset` directory is
kept in source control so designers can iterate on individual sizes
without re-running `sips`.
