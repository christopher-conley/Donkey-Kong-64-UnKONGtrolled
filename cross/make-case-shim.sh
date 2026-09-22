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
# See cross/build-windows.sh: ~/.xwin-cache/splat is where an unflagged
# `xwin splat` lands; the second path is a fallback for an existing splat.
SPLAT="${XWIN_SPLAT:-}"
[ -n "$SPLAT" ] || for _c in "$HOME/.xwin-cache/splat" "$HOME/.cache/xwin/splat"; do
    [ -d "$_c/crt/include" ] && { SPLAT="$_c"; break; }
done
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
# xwin names these "x86_64" by default, "x64" only with
# --preserve-ms-arch-notation. Probing matters more here than elsewhere: a
# wrong guess finds no directories,
# links nothing, reports "0 symlinks" as though that were a result, and the
# build fails twenty minutes later at the final link.
LIBDIRS=()
for _base in "$SPLAT/sdk/lib/um" "$SPLAT/sdk/lib/ucrt" "$SPLAT/crt/lib"; do
    for _a in x64 x86_64; do
        [ -d "$_base/$_a" ] && { LIBDIRS+=("$_base/$_a"); break; }
    done
done
[ ${#LIBDIRS[@]} -eq 3 ] || {
    echo "only found ${#LIBDIRS[@]} of 3 library directories under $SPLAT" >&2
    echo "  expected x64 or x86_64 under sdk/lib/um, sdk/lib/ucrt and crt/lib" >&2
    exit 1
}

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
# Zero is not a plausible outcome: the tree names .lib files whose casing on
# disk differs, which is the reason this script exists. Zero means the search
# found nothing to search, so say so here rather than at the final link.
[ "$liblinked" -gt 0 ] || {
    echo "no library symlinks created -- searched: ${LIBDIRS[*]}" >&2
    exit 1
}
