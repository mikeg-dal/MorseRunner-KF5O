#!/bin/sh
# Rebuild the C++ reference-dump tools and regenerate the Swift port's
# test fixtures. Compiles with -ffp-contract=off: clang otherwise fuses
# a*b+c into FMA on arm64, which Swift does not do, and the float
# results would differ in the last bits.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# Qt location: $QT_ROOT, else whatever the main build found, else Homebrew.
QT=${QT_ROOT:-}
if [ -z "$QT" ] && [ -f "$ROOT/build/arm64-release/CMakeCache.txt" ]; then
    QT=$(sed -n 's|^Qt6_DIR:PATH=\(.*\)/lib/cmake/Qt6$|\1|p' "$ROOT/build/arm64-release/CMakeCache.txt")
fi
[ -n "$QT" ] || QT=$(brew --prefix qt 2>/dev/null || true)
OUT="$ROOT/Swift/Sources/MRTestSupport/Fixtures"
# Separate build dirs let several people/agents regenerate at once.
BUILD=${GOLDEN_BUILD_DIR:-$ROOT/build/golden}
cmake -S "$ROOT" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$QT" \
    -DCMAKE_CXX_FLAGS="-ffp-contract=off" \
    -DMORSERUNNER_BUILD_TESTS=OFF \
    -DMORSERUNNER_BUILD_GOLDEN=ON >/dev/null
MODULES=${*:-random dsp scoring sim}
TARGETS=""
for t in $MODULES; do TARGETS="$TARGETS golden_$t"; done
# Build only what was asked for, so one module's work in progress
# can't break another's regeneration.
cmake --build "$BUILD" --parallel --target $TARGETS
for t in $MODULES; do
    "$BUILD/tools/golden/golden_$t" "$OUT"
    echo "golden_$t -> $OUT"
done
