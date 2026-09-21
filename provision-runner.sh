#!/bin/bash
# SPDX-FileCopyrightText: 2026 Christopher Conley
# SPDX-License-Identifier: MIT
#
# Provision a Debian self-hosted GitHub Actions runner to build this project.
#
# Everything here exists because its absence broke a real build, so the
# comments say which one. Safe to re-run: every step checks before acting.
#
#   provision-runner.sh           install everything, then verify
#   provision-runner.sh --check   verify only, change nothing
#
# Not done here, because both need secrets: registering the runner with
# GitHub, and placing the decompressed asset. Both are printed at the end.
set -uo pipefail

LLVM_VERSION="${LLVM_VERSION:-19}"       # upstream's Windows CI pins LLVM 19
CCACHE_VERSION="${CCACHE_VERSION:-4.14}" # Debian 12 ships 4.7.5, which cannot
                                         # cache this project's clang-cl calls
XWIN_VERSION="${XWIN_VERSION:-0.10.0}"
DIRECTX_HEADERS_DIR="${DIRECTX_HEADERS_DIR:-/opt/DirectX-Headers}"
RUNNER_USER="${RUNNER_USER:-actionsrunner}"
RUNNER_HOME="$(getent passwd "$RUNNER_USER" 2>/dev/null | cut -d: -f6)"
RUNNER_HOME="${RUNNER_HOME:-/home/$RUNNER_USER}"
XWIN_SPLAT="${XWIN_SPLAT:-$RUNNER_HOME/.xwin-cache/splat}"
CCACHE_DIR_PATH="${CCACHE_DIR_PATH:-$RUNNER_HOME/cache/ccache}"
VCPKG_CACHE="${VCPKG_CACHE:-$RUNNER_HOME/cache/vcpkg}"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m   %s\n' "$*"; }
bad()  { printf '    \033[31mMISS\033[0m %s\n' "$*"; FAILURES=$((FAILURES+1)); }
warn() { printf '    \033[33mwarn\033[0m %s\n' "$*"; }
as_runner() { sudo -u "$RUNNER_USER" "$@"; }

# ---------------------------------------------------------------- verification
# Mirrors the preflight steps in .github/workflows/build.yml. Anything missing
# here fails a build there, so it is better found now.
verify() {
    FAILURES=0

    say "Tools"
    # git: actions/checkout silently falls back to a REST API tarball download
    # without it, and that path cannot do submodules.
    # clang + ld.lld: patches/ cross-compiles to MIPS; CMakeLists.txt defaults
    # PATCHES_C_COMPILER and PATCHES_LD to them by bare name.
    for t in git cmake ninja gcc g++ clang ld.lld ccache \
             clang-cl lld-link llvm-lib llvm-rc llvm-mt wine gendef \
             x86_64-w64-mingw32-gcc zip curl; do
        if command -v "$t" >/dev/null; then ok "$t -> $(command -v "$t")"; else bad "$t"; fi
    done

    say "ccache is new enough to cache clang-cl"
    if command -v ccache >/dev/null; then
        v=$(ccache --version | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        major=${v%%.*}; minor=$(echo "$v" | cut -d. -f2)
        # 4.7.5 reports every clang-cl call "uncacheable: compiler output file
        # missing" and exits 0, so the build is simply slow with no signal.
        # Only 4.7.5 (bad) and 4.12.3 (good) have actually been tested; the
        # threshold below is set so Debian trixie's 4.11.2 passes. The
        # authoritative check is in the workflow, which warns when a run
        # produced no cacheable compilations at all.
        if [ "$major" -gt 4 ] || { [ "$major" -eq 4 ] && [ "$minor" -ge 10 ]; }; then
            ok "ccache $v"
        else
            bad "ccache $v is too old (4.7.5 cannot cache clang-cl; 4.12.3+ can)"
        fi
    fi

    say "Static libstdc++"
    # CMakeLists.txt links -static-libstdc++, so a 64-bit libstdc++.a must exist
    # for the compiler in use or the Linux build dies at the final link.
    if command -v g++ >/dev/null; then
        p=$(g++ -print-file-name=libstdc++.a)
        case "$p" in
            /*) [ -f "$p" ] && ok "libstdc++.a -> $p" || bad "libstdc++.a path is not a file: $p" ;;
            *)  bad "no 64-bit libstdc++.a for g++" ;;
        esac
    fi

    say "xwin splat"
    if [ -d "$XWIN_SPLAT/crt/include" ]; then
        ok "splat at $XWIN_SPLAT"
        # xwin has shipped the x86-64 libraries under both names.
        um=""
        for a in x64 x86_64; do
            [ -d "$XWIN_SPLAT/sdk/lib/um/$a" ] && { um="$XWIN_SPLAT/sdk/lib/um/$a"; break; }
        done
        if [ -n "$um" ]; then
            ok "library dir $um"
            # lld-link is case-sensitive where MSVC was not: the SDK ships
            # kernel32.Lib and the implicit link set asks for kernel32.lib.
            if [ -e "$um/kernel32.lib" ]; then ok "lowercase kernel32.lib resolves"
            else bad "$um has no lowercase kernel32.lib -- re-splat with symlinks enabled"; fi
        else
            bad "no x64 or x86_64 directory under $XWIN_SPLAT/sdk/lib/um"
        fi
    else
        bad "no xwin splat at $XWIN_SPLAT"
    fi

    say "DirectX-Headers"
    # The Windows SDK xwin fetches predates D3D12_HEAP_TYPE_GPU_UPLOAD, and
    # Debian packages these nowhere.
    if [ -e "$DIRECTX_HEADERS_DIR/include/directx/d3d12.h" ]; then
        ok "$DIRECTX_HEADERS_DIR/include"
    elif [ -e /usr/x86_64-w64-mingw32/sys-root/mingw/include/directx/d3d12.h ]; then
        ok "system mingw DirectX-Headers"
    else
        bad "no DirectX-Headers (expected $DIRECTX_HEADERS_DIR/include/directx/d3d12.h)"
    fi

    say "Writable cache directories"
    for d in "$CCACHE_DIR_PATH" "$VCPKG_CACHE"; do
        if [ -d "$d" ]; then
            # Root-owned cache directories make every lookup silently miss.
            owner=$(stat -c %U "$d")
            [ "$owner" = "$RUNNER_USER" ] && ok "$d (owned by $owner)" \
                                          || bad "$d is owned by $owner, not $RUNNER_USER"
        else
            warn "$d does not exist yet (the workflow creates it)"
        fi
    done

    say "Runner environment file"
    envf="$RUNNER_HOME/actions-runner/.env"
    if [ -f "$envf" ]; then
        # A shell profile does NOT work: job steps run non-interactive and
        # systemd does not read .bashrc. Only this file reaches the job.
        for k in XWIN_SPLAT DIRECTX_HEADERS VCPKG_DEFAULT_BINARY_CACHE; do
            grep -q "^${k}=" "$envf" && ok "$k set in .env" || bad "$k missing from .env"
        done
    else
        bad "no $envf (job steps do not read .bashrc or the user's profile)"
    fi

    echo
    if [ "$FAILURES" -eq 0 ]; then
        printf '\033[32mAll checks passed.\033[0m\n'
    else
        printf '\033[31m%d check(s) failed.\033[0m\n' "$FAILURES"
    fi
    return "$FAILURES"
}

if [ "$CHECK_ONLY" -eq 1 ]; then
    verify
    exit $?
fi

# -------------------------------------------------------------- provisioning
[ "$(id -u)" -eq 0 ] || { echo "run as root (or under sudo) to install; use --check to verify only" >&2; exit 1; }

say "APT packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl git gnupg xz-utils zip unzip tar \
    build-essential cmake ninja-build pkg-config python3 \
    libsdl2-dev libgtk-3-dev libcurl4-openssl-dev libfreetype-dev zlib1g-dev \
    libx11-dev libxext-dev libxrandr-dev libsm-dev libice-dev \
    wine mingw-w64 mingw-w64-tools

say "LLVM $LLVM_VERSION"
if ! command -v "clang-$LLVM_VERSION" >/dev/null; then
    codename=$(. /etc/os-release && echo "${VERSION_CODENAME}")
    install -d -m0755 /usr/share/keyrings
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/llvm.gpg
    echo "deb [signed-by=/usr/share/keyrings/llvm.gpg] http://apt.llvm.org/${codename}/ llvm-toolchain-${codename}-${LLVM_VERSION} main" \
        > /etc/apt/sources.list.d/llvm.list
    apt-get update
fi
apt-get install -y --no-install-recommends \
    "clang-$LLVM_VERSION" "lld-$LLVM_VERSION" "llvm-$LLVM_VERSION"

say "Unversioned names for the LLVM tools"
# Debian does not create generic names for these, and everything that uses them
# -- CMakeLists.txt's PATCHES_LD, the cross toolchain file, the workflow
# preflight -- refers to them by bare name.
for t in clang clang++ clang-cl lld-link ld.lld llvm-lib llvm-rc llvm-mt llvm-dlltool; do
    src="/usr/lib/llvm-$LLVM_VERSION/bin/$t"
    [ -x "$src" ] && ln -sfn "$src" "/usr/local/bin/$t" && ok "$t -> $src"
done

say "ccache $CCACHE_VERSION (static)"
# Deliberately not the apt package: Debian 12 ships 4.7.5, which reports every
# clang-cl compilation uncacheable and exits successfully, so the cache is
# inert and nothing says so.
if ! ccache --version 2>/dev/null | grep -q "$CCACHE_VERSION"; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/ccache.tar.xz" \
        "https://github.com/ccache/ccache/releases/download/v${CCACHE_VERSION}/ccache-${CCACHE_VERSION}-linux-x86_64-musl-static.tar.xz"
    tar xf "$tmp/ccache.tar.xz" -C "$tmp"
    bin=$(find "$tmp" -type f -name ccache -perm -u+x | head -1)
    [ -n "$bin" ] || { echo "ccache binary not found in the tarball" >&2; exit 1; }
    install -m0755 "$bin" /usr/local/bin/ccache
    rm -rf "$tmp"
fi
ok "$(/usr/local/bin/ccache --version | head -1)"

say "DirectX-Headers"
if [ ! -e "$DIRECTX_HEADERS_DIR/include/directx/d3d12.h" ]; then
    rm -rf "$DIRECTX_HEADERS_DIR"
    git clone --depth 1 https://github.com/microsoft/DirectX-Headers "$DIRECTX_HEADERS_DIR"
fi
ok "$DIRECTX_HEADERS_DIR"

say "xwin $XWIN_VERSION and the SDK splat"
if ! command -v xwin >/dev/null; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/xwin.tar.gz" \
        "https://github.com/Jake-Shadle/xwin/releases/download/${XWIN_VERSION}/xwin-${XWIN_VERSION}-x86_64-unknown-linux-musl.tar.gz"
    tar xf "$tmp/xwin.tar.gz" -C "$tmp"
    bin=$(find "$tmp" -type f -name xwin -perm -u+x | head -1)
    [ -n "$bin" ] || { echo "xwin binary not found in the tarball" >&2; exit 1; }
    install -m0755 "$bin" /usr/local/bin/xwin
    rm -rf "$tmp"
fi
if [ ! -d "$XWIN_SPLAT/crt/include" ]; then
    # Run as the runner user so the splat and its cache are owned correctly.
    # Symlinks are left enabled on purpose: lld-link cannot resolve the SDK's
    # original casing without them. --preserve-ms-arch-notation is likewise
    # not passed: the default x86_64 naming is what an unflagged splat gives,
    # and the toolchain probes for either.
    as_runner env HOME="$RUNNER_HOME" \
        xwin --accept-license --cache-dir "$RUNNER_HOME/.xwin-cache" splat \
             --output "$XWIN_SPLAT"
fi
ok "$XWIN_SPLAT"

say "Cache directories"
for d in "$CCACHE_DIR_PATH" "$VCPKG_CACHE"; do
    install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m0755 "$d"
    ok "$d"
done

say "Runner .env"
envf="$RUNNER_HOME/actions-runner/.env"
if [ -d "$(dirname "$envf")" ]; then
    touch "$envf"; chown "$RUNNER_USER:$RUNNER_USER" "$envf"
    set_env() {
        if grep -q "^$1=" "$envf"; then sed -i "s|^$1=.*|$1=$2|" "$envf"
        else printf '%s=%s\n' "$1" "$2" >> "$envf"; fi
    }
    set_env XWIN_SPLAT "$XWIN_SPLAT"
    set_env DIRECTX_HEADERS "$DIRECTX_HEADERS_DIR/include"
    set_env VCPKG_DEFAULT_BINARY_CACHE "$VCPKG_CACHE"
    ok "$envf"
    warn "restart the runner service: .env is read only at startup"
else
    warn "no $(dirname "$envf") yet -- register the runner, then re-run this script"
fi

verify
rc=$?

cat <<EOF

Remaining, because both involve secrets this script will not handle:

  1. Register the runner (label: self-hosted) if it is not already, then
     restart it so the .env above is picked up.
  2. Place the decompressed asset outside the runner workspace -- anything
     inside it is deleted by actions/checkout's git clean -ffdx -- and set
     the DECOMPRESSED_ASSET_PATH and ASSET_FILENAME repository secrets.
EOF
exit "$rc"
