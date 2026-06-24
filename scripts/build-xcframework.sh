#!/usr/bin/env bash
#
# Reproducibly build plist.xcframework (+ per-slice static libs and headers)
# from a pinned libplist release tag.
#
#   - Clones libimobiledevice/libplist at $LIBPLIST_TAG
#   - Runs autogen/configure once (native) to generate a correct config.h
#     (the HAVE_* / endianness values are identical across all Apple/Darwin
#      platforms, so the same config.h is reused for every slice)
#   - Compiles the C library (libplist-2.0 + libcnary) and the C++ wrapper
#     (libplist++-2.0) directly with clang for each platform slice
#   - Builds NO tools/tests, so the archives contain no `main` symbol
#   - Emits artifacts into the repository root
#
# Output (relative to repo root):
#   plist.xcframework/         multi-platform binary framework (SwiftPM binaryTarget)
#   libplist-macos.a           macOS static lib (arm64 + x86_64)
#   libplist-ios.a             iOS device static lib (arm64)
#   libplist-ios-sim.a         iOS simulator static lib (arm64 + x86_64)
#   include/plist/*.h          public headers (so <plist/plist.h> resolves with -Iinclude)
#   LICENSE / COPYING.LESSER   upstream LGPL-2.1 license text
#
# Usage:  scripts/build-xcframework.sh
# Env:    LIBPLIST_TAG (default 2.7.0), MIN_IOS (default 13.0), MIN_MAC (default 11.0)
#
set -euo pipefail

LIBPLIST_TAG="${LIBPLIST_TAG:-2.7.0}"
MIN_IOS="${MIN_IOS:-13.0}"
MIN_MAC="${MIN_MAC:-11.0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/libplist-build.XXXXXX")"
SRC="$BUILD/libplist"
OUT="$BUILD/out"
trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$OUT/lib"

echo "==> libplist tag: $LIBPLIST_TAG   min iOS: $MIN_IOS"
echo "==> cloning ..."
git clone --quiet --depth 1 --branch "$LIBPLIST_TAG" \
    https://github.com/libimobiledevice/libplist.git "$SRC"

echo "==> generating build system + config.h (native) ..."
( cd "$SRC"
  export LIBTOOLIZE=glibtoolize
  NOCONFIGURE=1 ./autogen.sh >/dev/null 2>&1
  ./configure --without-cython --enable-static --disable-shared >/dev/null 2>&1 )

# --- authoritative source lists (parsed from the upstream Makefile.am) ------
# C library sources (src/*.c) listed in libplist_2_0_la_SOURCES
read -r -a CFILES <<<"$(awk '/libplist_2_0_la_SOURCES[[:space:]]*=/{f=1} f{print} /[^\\]$/{if(f)exit}' "$SRC/src/Makefile.am" | grep -oE '[A-Za-z0-9_-]+\.c\b' | sed 's/\.c$//' | tr '\n' ' ')"
# C++ wrapper sources (src/*.cpp) listed in libplist___2_0_la_SOURCES
read -r -a CPPFILES <<<"$(awk '/libplist___2_0_la_SOURCES[[:space:]]*=/{f=1} f{print} /[^\\]$/{if(f)exit}' "$SRC/src/Makefile.am" | grep -oE '[A-Za-z0-9_-]+\.cpp\b' | sed 's/\.cpp$//' | tr '\n' ' ')"
# libcnary convenience-lib sources
read -r -a CNARY <<<"$(awk '/libcnary_la_SOURCES[[:space:]]*=/{f=1} f{print} /[^\\]$/{if(f)exit}' "$SRC/libcnary/Makefile.am" | grep -oE '[A-Za-z0-9_-]+\.c\b' | sed 's/\.c$//' | tr '\n' ' ')"

echo "==> C sources   : ${CFILES[*]}"
echo "==> C++ sources : ${CPPFILES[*]}"
echo "==> cnary       : ${CNARY[*]}"
[ "${#CFILES[@]}" -ge 10 ] || { echo "ERROR: failed to parse C source list"; exit 1; }

INCS=( -DHAVE_CONFIG_H -I"$SRC" -I"$SRC/include" -I"$SRC/src" -I"$SRC/libcnary/include" )

# build_slice <name> <sdk> <min-version-flag> <arch flags...>
build_slice() {
  local name="$1" sdk="$2" minflag="$3"; shift 3
  local archflags=( "$@" )
  local sdkpath; sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local objdir="$OUT/obj/$name"; rm -rf "$objdir"; mkdir -p "$objdir"
  local common=( "${archflags[@]}" -isysroot "$sdkpath" "$minflag" -O2 -fvisibility=hidden -fvisibility-inlines-hidden )

  echo "==> [$name] compiling ..."
  for f in "${CFILES[@]}"; do clang   "${common[@]}"            "${INCS[@]}" -c "$SRC/src/$f.c"      -o "$objdir/$f.o"; done
  for f in "${CNARY[@]}";  do clang   "${common[@]}"            "${INCS[@]}" -c "$SRC/libcnary/$f.c" -o "$objdir/cnary_$f.o"; done
  for f in "${CPPFILES[@]}";do clang++ "${common[@]}" -std=c++11 "${INCS[@]}" -c "$SRC/src/$f.cpp"   -o "$objdir/$f.oxx"; done

  echo "==> [$name] archiving ..."
  libtool -static -o "$OUT/lib/libplist-$name.a" "$objdir"/*.o "$objdir"/*.oxx
}

# ---- platform slices -------------------------------------------------------
build_slice macos   macosx          "-mmacosx-version-min=$MIN_MAC"        -arch arm64 -arch x86_64
build_slice ios     iphoneos        "-miphoneos-version-min=$MIN_IOS"      -arch arm64
build_slice ios-sim iphonesimulator "-mios-simulator-version-min=$MIN_IOS" -arch arm64 -arch x86_64

# ---- public headers + clang module map -------------------------------------
echo "==> assembling headers ..."
rm -rf "$OUT/headers"; mkdir -p "$OUT/headers/plist"
cp "$SRC"/include/plist/*.h "$OUT/headers/plist/"
cat > "$OUT/headers/module.modulemap" <<'EOF'
module plist {
    header "plist/plist.h"
    export *
}
EOF

# ---- create the xcframework ------------------------------------------------
echo "==> creating plist.xcframework ..."
rm -rf "$OUT/plist.xcframework"
xcodebuild -create-xcframework \
  -library "$OUT/lib/libplist-macos.a"   -headers "$OUT/headers" \
  -library "$OUT/lib/libplist-ios.a"     -headers "$OUT/headers" \
  -library "$OUT/lib/libplist-ios-sim.a" -headers "$OUT/headers" \
  -output "$OUT/plist.xcframework" >/dev/null

# ---- publish artifacts into the repo root ----------------------------------
echo "==> publishing artifacts to repo root ..."
rm -rf "$REPO_ROOT/plist.xcframework" "$REPO_ROOT/include"
cp -R "$OUT/plist.xcframework" "$REPO_ROOT/plist.xcframework"
cp "$OUT/lib/libplist-macos.a"   "$REPO_ROOT/libplist-macos.a"
cp "$OUT/lib/libplist-ios.a"     "$REPO_ROOT/libplist-ios.a"
cp "$OUT/lib/libplist-ios-sim.a" "$REPO_ROOT/libplist-ios-sim.a"
mkdir -p "$REPO_ROOT/include/plist"
cp "$SRC"/include/plist/*.h "$REPO_ROOT/include/plist/"
cp "$OUT/headers/module.modulemap" "$REPO_ROOT/include/module.modulemap"
cp "$SRC/COPYING.LESSER" "$REPO_ROOT/COPYING.LESSER"
cp "$SRC/COPYING"        "$REPO_ROOT/COPYING"
cp "$SRC/COPYING.LESSER" "$REPO_ROOT/LICENSE"

echo "==> DONE. libplist $LIBPLIST_TAG -> $REPO_ROOT"
