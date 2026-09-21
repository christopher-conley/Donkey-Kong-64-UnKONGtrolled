#!/bin/bash
# SPDX-FileCopyrightText: 2026 Christopher Conley
# SPDX-License-Identifier: MIT
# Cross-compile DK64UnKONGtrolled.exe for Windows (x64, MSVC ABI) from Linux.
#
# Uses clang-cl + lld-link against an xwin-provided Windows SDK, which is the same
# compiler the project's own Windows CI job uses -- so every vendored header takes its
# MSVC branch and no source patching is required.
#
# Requirements:
#   clang-cl, lld-link, llvm-lib, llvm-rc, llvm-mt, cmake, ninja   (clang + llvm)
#   wine                     -- runs the Windows dxc.exe to compile and SIGN shaders
#   gendef                   -- mingw-w64-tools, for the libcurl import library
#   an xwin splat            -- xwin --accept-license splat   (~2.4 GB, one time;
#                               lands in ~/.xwin-cache/splat)
#   DirectX-Headers          -- the SDK xwin fetches predates D3D12_HEAP_TYPE_GPU_UPLOAD
#
# Usage: cross/build-windows.sh [build-dir]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${1:-$REPO/build-win}"
# xwin writes to ./.xwin-cache/splat by default, so the documented
# `xwin --accept-license splat` leaves it at ~/.xwin-cache/splat. This script
# previously defaulted to ~/.cache/xwin/splat, which was never an xwin default:
# it was where an unrelated project's splat happened to sit on the machine this
# was first written on. That path is still checked, so such a splat keeps
# working, but it is the fallback rather than the assumption.
if [ -z "${XWIN_SPLAT:-}" ]; then
    for _c in "$HOME/.xwin-cache/splat" "$HOME/.cache/xwin/splat"; do
        [ -d "$_c/crt/include" ] && { XWIN_SPLAT="$_c"; break; }
    done
    : "${XWIN_SPLAT:=$HOME/.xwin-cache/splat}"
fi
: "${DIRECTX_HEADERS:=}"
CURL_PREFIX="$REPO/vcpkg_installed/x64-mingw-dynamic-release"

export XWIN_SPLAT DIRECTX_HEADERS

[ -d "$XWIN_SPLAT/sdk/include/um" ] || { echo "no xwin splat at $XWIN_SPLAT" >&2; exit 1; }
# DirectX-Headers: the toolchain file falls back to cross/directx-headers, so this is
# only a check that at least one source exists.
if [ ! -e "$REPO/cross/directx-headers/directx/d3d12.h" ] \
   && [ ! -e "/usr/x86_64-w64-mingw32/sys-root/mingw/include/directx/d3d12.h" ] \
   && { [ -z "$DIRECTX_HEADERS" ] || [ ! -e "$DIRECTX_HEADERS/directx/d3d12.h" ]; }; then
    echo "No DirectX-Headers. Install mingw64-directx-headers, or extract it without root:" >&2
    echo "  dnf download mingw64-directx-headers && rpm2cpio *.rpm | cpio -idm" >&2
    exit 1
fi

echo "==> generating case-correcting shims"
"$REPO/cross/make-case-shim.sh"

echo "==> generating libcurl import library"
"$REPO/cross/make-curl-implib.sh"

echo "==> recompiler output"
[ -f "$REPO/RecompiledFuncs/funcs_0.c" ] || (cd "$REPO" && ./N64Recomp us.toml && ./RSPRecomp n_aspMain.toml)

echo "==> configure"
# NOTE: CMAKE_*_FLAGS_INIT only seeds a fresh cache. Editing the toolchain file and
# re-running configure over an existing build dir silently changes nothing.
rm -rf "$BUILD"
# ccache if it is installed, since this script is also run by hand. The build
# directory is removed above and, in CI, the checkout is cleaned before every
# run, so the compiler cache is the only thing that carries work between builds.
CCACHE_ARGS=()
if command -v ccache >/dev/null; then
    CCACHE_ARGS=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
    echo "    using ccache ($(ccache --version | head -1))"
fi
cmake -S "$REPO" -B "$BUILD" -G Ninja \
    "${CCACHE_ARGS[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$REPO/xwin-clang-cl.cmake" \
    -DVCPKG_MANIFEST_MODE=OFF \
    -DCURL_LIBRARY="$REPO/cross/winlib/libcurl.lib" \
    -DCURL_INCLUDE_DIR="$CURL_PREFIX/include" \
    -DPATCHES_C_COMPILER=clang -DPATCHES_LD=ld.lld

echo "==> build"
WINEDEBUG="${WINEDEBUG:--all}" cmake --build "$BUILD" --target DK64Recompiled -j"$(nproc)"

echo "==> staging runtime files"
DIST="$BUILD/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
cp "$BUILD/DK64UnKONGtrolled.exe" "$DIST/"
cp "$BUILD/SDL2.dll" "$BUILD/dxcompiler.dll" "$BUILD/dxil.dll" "$DIST/"
# Everything in the triplet's bin/ is a runtime dependency of libcurl. Globbed rather
# than named because vcpkg's zlib port has shipped the DLL as both libzlib1.dll and
# libz.dll depending on the vcpkg revision, and a missing name fails the build here,
# after everything has already compiled.
cp "$CURL_PREFIX"/bin/*.dll "$DIST/"
cp -r "$REPO/assets" "$DIST/"
[ -f "$REPO/recompcontrollerdb.txt" ] && cp "$REPO/recompcontrollerdb.txt" "$DIST/"

echo
echo "built: $DIST/DK64UnKONGtrolled.exe"
echo "NOTE: needs the Microsoft Visual C++ 2015-2022 Redistributable on the target"
echo "      machine (VCRUNTIME140.dll / MSVCP140.dll), same as the official builds."
