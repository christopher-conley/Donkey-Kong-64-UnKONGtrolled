#!/bin/bash
# SPDX-FileCopyrightText: 2026 Christopher Conley
# SPDX-License-Identifier: MIT
# Produce MSVC-ABI import libraries for the libcurl DLL, for the clang-cl cross build.
#
# vcpkg builds libcurl for the x64-mingw-dynamic-release triplet, which yields a DLL plus
# a MinGW .dll.a that lld-link cannot use. libcurl's public interface is plain C, so an
# import library generated from the DLL's own export table is a correct way to link it --
# the shipped DLL is still the one vcpkg built.
#
# Two names are produced because CMake's FindCURL reads libcurl.pc and appends a bare
# -lcurl (=> curl.lib) in addition to the full path it is given.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${CURL_BIN_DIR:-$REPO/vcpkg_installed/x64-mingw-dynamic-release/bin}"
OUT="$REPO/cross/winlib"

[ -f "$SRC/libcurl.dll" ] || { echo "no libcurl.dll in $SRC" >&2; exit 1; }

mkdir -p "$OUT"
cd "$OUT"
gendef "$SRC/libcurl.dll" >/dev/null
llvm-dlltool -m i386:x86-64 -d libcurl.def -l libcurl.lib
cp libcurl.lib curl.lib
rm -f libcurl.def
echo "wrote $OUT/libcurl.lib and $OUT/curl.lib"
