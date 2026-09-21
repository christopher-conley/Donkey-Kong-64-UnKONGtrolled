#!/bin/bash
# SPDX-FileCopyrightText: 2026 Christopher Conley
# SPDX-License-Identifier: MIT
# Build a directory of case-correcting symlinks for the xwin Windows SDK.
#
# Windows filesystems are case-insensitive, so source that includes <Shlobj.h> builds
# fine on Windows against a file named ShlObj.h. On Linux it does not. xwin creates an
# all-lowercase symlink beside each header, which covers <shlobj.h> but not the mixed
# casings real code actually uses.
#
# Only names that do NOT exist in the source tree are linked: RmlUi ships its own
# Math.h and Memory.h, and shadowing those with the Windows SDK versions would be a
# very confusing failure.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPLAT="${XWIN_SPLAT:-$HOME/.cache/xwin/splat}"
SHIM="$REPO/cross/case-shim"
LIBSHIM="$REPO/cross/case-shim-lib"

[ -d "$SPLAT/sdk/include/um" ] || { echo "no xwin splat at $SPLAT" >&2; exit 1; }

rm -rf "$SHIM" "$LIBSHIM"; mkdir -p "$SHIM" "$LIBSHIM"

SEARCH=("$SPLAT/sdk/include/um" "$SPLAT/sdk/include/shared" "$SPLAT/sdk/include/ucrt" "$SPLAT/crt/include")

mapfile -t NAMES < <(
    grep -rhoE '#[ \t]*include[ \t]*[<"][A-Za-z0-9_]+\.h[>"]' \
        --include=*.c --include=*.cpp --include=*.h --include=*.hpp \
        "$REPO/lib/rt64/src" "$REPO/lib/N64ModernRuntime" "$REPO/lib/RecompFrontend" "$REPO/src" 2>/dev/null \
      | grep -oE '[<"][A-Za-z0-9_]+\.h[>"]' | tr -d '<>"' | grep -E '^[A-Z]' | sort -u
)

linked=0
for n in "${NAMES[@]}"; do
    # Already resolvable under this exact name? Nothing to do.
    found_exact=""
    for d in "${SEARCH[@]}"; do [ -e "$d/$n" ] && { found_exact=1; break; }; done
    [ -n "$found_exact" ] && continue

    # A project header of the same name wins; never shadow it.
    if find "$REPO/lib" "$REPO/src" -name "$n" -print -quit 2>/dev/null | grep -q .; then
        continue
    fi

    for d in "${SEARCH[@]}"; do
        real=$(find "$d" -maxdepth 1 -iname "$n" -print -quit 2>/dev/null || true)
        if [ -n "$real" ]; then
            ln -sf "$real" "$SHIM/$n"
            echo "  $n -> $(basename "$real")"
            linked=$((linked + 1))
            break
        fi
    done
done

echo "$linked case-correcting symlink(s) in $SHIM"

# --- library names ---
# Same problem one layer down: rt64 links Shcore.lib, the top-level CMakeLists links
# Winmm.lib, and the SDK ships shcore.lib / SHCORE.lib / WinMM.Lib. lld-link does not
# guess, so link case-correcting symlinks for every .lib named in a CMakeLists here.
LIBDIRS=("$SPLAT/sdk/lib/um/x64" "$SPLAT/sdk/lib/ucrt/x64" "$SPLAT/crt/lib/x64")

mapfile -t LIBS < <(
    grep -rhoE '\b[A-Za-z0-9_]+\.[Ll][Ii][Bb]\b' \
        --include=CMakeLists.txt --include=*.cmake \
        "$REPO/CMakeLists.txt" "$REPO/lib/rt64" "$REPO/lib/RecompFrontend" "$REPO/lib/N64ModernRuntime" 2>/dev/null \
      | sort -u
)

liblinked=0
for l in "${LIBS[@]}"; do
    found_exact=""
    for d in "${LIBDIRS[@]}"; do [ -e "$d/$l" ] && { found_exact=1; break; }; done
    [ -n "$found_exact" ] && continue
    for d in "${LIBDIRS[@]}"; do
        real=$(find "$d" -maxdepth 1 -iname "$l" -print -quit 2>/dev/null || true)
        if [ -n "$real" ]; then
            ln -sf "$real" "$LIBSHIM/$l"
            echo "  $l -> $(basename "$real")"
            liblinked=$((liblinked + 1))
            break
        fi
    done
done
echo "$liblinked case-correcting library symlink(s) in $LIBSHIM"
