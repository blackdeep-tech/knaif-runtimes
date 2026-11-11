#!/usr/bin/env bash
# Build the media pack for macOS: the same reduced, static GPL ffmpeg/ffprobe as build.sh makes for
# Windows and Linux, built natively on a Mac (BtbN's FFmpeg-Builds has no macOS target).
#
#   bash ffmpeg/build-macos.sh <line> <out-dir>      # on the Mac; arch = the Mac's (arm64)
#   bash ffmpeg/build-macos.sh --pins                 # print what would be built, anywhere
#
# Same inputs as the other platforms: every library is taken at the commit (or revision) that its
# stage script in BtbN's FFmpeg-Builds pins, at the BtbN commit in PINS, and ffmpeg at the release
# tag PINS names for the line, with the same configuration as variants/*-knaif.sh. Only the build
# steps are this script's own (native clang instead of BtbN's docker cross-builds). libiconv is the
# one exception: macOS ships it as a system library, and ffmpeg uses that copy.
#
# Needs: Xcode command line tools, and from Homebrew (build time only, nothing of them is linked):
#   brew install autoconf automake libtool pkgconf cmake meson ninja nasm subversion xz
# The result links only system libraries (libSystem, libiconv, libc++); the script refuses a
# binary that links anything else, so a Homebrew library can never slip into the pack.
# Work folder: $KNAIF_RUNTIMES_WORK (default ~/.cache/knaif-runtimes)/macos-<line>.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Written for macOS's own /bin/bash 3.2: no `mapfile`, no `source <(...)`.
eval "$(grep -E '^[A-Z0-9_]+=' "$HERE/PINS")"
KEEP=()
while IFS= read -r l; do KEEP+=("$l"); done < <(grep -v -E '^[[:space:]]*(#|$)' "$HERE/allowlist.txt")
# The libraries this build compiles, in dependency order (ogg before vorbis and theora). The
# allowlist's other stages are Windows-only (mingw*), build infrastructure (base, xorg-macros) or
# provided by macOS (libiconv).
LIBS=(zlib x264 x265 libmp3lame libopus libvpx svtav1 libogg libvorbis libtheora libwebp dav1d)
MIN_MACOS=${MACOSX_DEPLOYMENT_TARGET:-12.0}   # knaif's macOS floor
WORKROOT=${KNAIF_RUNTIMES_WORK:-$HOME/.cache/knaif-runtimes}
BTBN=$WORKROOT/btbn-$BTBN_COMMIT

btbn_checkout() {
    if [ ! -d "$BTBN/.git" ]; then git clone --quiet "$BTBN_REPO" "$BTBN"; fi
    git -C "$BTBN" fetch --quiet origin "$BTBN_COMMIT" 2>/dev/null || true
    git -C "$BTBN" checkout --quiet --force "$BTBN_COMMIT"
}

# `<repo> <commit-or-rev> <kind>` for a library, read from its BtbN stage script.
pin() {  # name
    local f
    f=$(ls "$BTBN"/scripts.d/??-"$1".sh 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "no BtbN stage for $1 at $BTBN_COMMIT" >&2; return 1; }
    (
        set +eu
        SCRIPT_REPO="" SCRIPT_COMMIT="" SCRIPT_REV=""
        # shellcheck source=/dev/null
        source "$f"
        if [ -n "$SCRIPT_REV" ]; then echo "$SCRIPT_REPO $SCRIPT_REV svn"
        else echo "$SCRIPT_REPO $SCRIPT_COMMIT git"; fi
    )
}

for s in "${LIBS[@]}"; do
    case " ${KEEP[*]} " in *" $s "*) ;; *) echo "build-macos.sh builds $s, which allowlist.txt does not keep" >&2; exit 1 ;; esac
done

if [ "${1:-}" = "--pins" ]; then
    btbn_checkout
    echo "BtbN $BTBN_COMMIT; ffmpeg tags: $(grep -E '^FFMPEG_TAG_' "$HERE/PINS" | tr '\n' ' ')"
    for s in "${LIBS[@]}"; do printf '%-11s %s\n' "$s" "$(pin "$s")"; done
    exit 0
fi

LINE=${1:?usage: build-macos.sh <line> <out-dir> | --pins}
OUT_ARG=${2:?usage: build-macos.sh <line> <out-dir> | --pins}
TAG_VAR="FFMPEG_TAG_${LINE//./_}"
FFMPEG_TAG=${!TAG_VAR:?no ffmpeg tag pinned for line $LINE in PINS}
[ "$(uname -s)" = Darwin ] || { echo "build-macos.sh runs on macOS" >&2; exit 1; }
for tool in git svn autoreconf libtoolize pkg-config cmake meson ninja nasm xz; do
    command -v "$tool" >/dev/null || command -v "g$tool" >/dev/null \
        || { echo "missing build tool: $tool (see the header)" >&2; exit 1; }
done
# Homebrew installs GNU libtoolize as glibtoolize (Apple's libtool is a different program).
command -v libtoolize >/dev/null || export LIBTOOLIZE=glibtoolize
mkdir -p "$OUT_ARG"
OUT=$(cd "$OUT_ARG" && pwd)
ARCH=$(uname -m)
WORK=$WORKROOT/macos-$LINE-$ARCH
SRC=$WORK/src
PREFIX=$WORK/prefix
rm -rf "$WORK"
mkdir -p "$SRC" "$PREFIX"
JOBS=$(sysctl -n hw.ncpu)
export MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig   # only our own .pc files, never Homebrew's
export CFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-mmacosx-version-min=$MIN_MACOS"
btbn_checkout

fetch() {  # name -> $SRC/<name>, at its pinned commit
    local repo ref kind dir=$SRC/$1
    read -r repo ref kind <<<"$(pin "$1")"
    if [ "$kind" = svn ]; then
        svn checkout --quiet "$repo@$ref" "$dir"
    else
        git init --quiet "$dir"
        git -C "$dir" remote add origin "$repo"
        if ! git -C "$dir" fetch --quiet --depth 1 origin "$ref" 2>/dev/null; then
            git -C "$dir" fetch --quiet origin   # a server that will not serve a commit by hash
        fi
        git -C "$dir" checkout --quiet "$ref"
    fi
    echo "$1 $repo $ref" >> "$WORK/pins.txt"
}

autotools() {  # dir, configure args...
    local dir=$1
    shift
    (cd "$dir" && { [ -x ./autogen.sh ] && NOCONFIGURE=1 ./autogen.sh || autoreconf -fi; } \
        && ./configure --prefix="$PREFIX" --disable-shared --enable-static "$@" \
        && make -j"$JOBS" && make install)
}

build_lib() {  # name
    local d=$SRC/$1
    case $1 in
        zlib)
            (cd "$d" && ./configure --prefix="$PREFIX" --static && make -j"$JOBS" && make install) ;;
        x264)
            (cd "$d" && ./configure --prefix="$PREFIX" --disable-cli --enable-static --enable-pic \
                --disable-lavf --disable-swscale && make -j"$JOBS" && make install) ;;
        x265)
            # BtbN's layout: 12-bit and 10-bit builds linked into the 8-bit one.
            local common=(-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release
                -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ALPHA=ON
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" ${X265_CMAKE_EXTRA:-})
            # As BtbN does: json11.cpp uses fixed-width integers without including <cstdint>.
            local j=$d/source/dynamicHDR10/json11/json11.cpp
            { printf '#include <cstdint>\n'; cat "$j"; } > "$j.tmp" && mv "$j.tmp" "$j"
            (cd "$d" &&
                cmake "${common[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -DMAIN12=ON -S source -B 12bit &&
                cmake "${common[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -S source -B 10bit &&
                cmake --build 12bit -j "$JOBS" && cmake --build 10bit -j "$JOBS" &&
                mkdir -p 8bit && cp 12bit/libx265.a 8bit/libx265_main12.a && cp 10bit/libx265.a 8bit/libx265_main10.a &&
                cmake "${common[@]}" -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L. \
                    -DLINKED_10BIT=ON -DLINKED_12BIT=ON -S source -B 8bit &&
                cmake --build 8bit -j "$JOBS" &&
                mv 8bit/libx265.a 8bit/libx265_main.a &&
                libtool -static -o 8bit/libx265.a 8bit/libx265_main.a 8bit/libx265_main10.a 8bit/libx265_main12.a &&
                cmake --install 8bit &&
                echo "Libs.private: -lc++" >> "$PREFIX/lib/pkgconfig/x265.pc") ;;
        libmp3lame)
            (cd "$d" && autoreconf -fi && CFLAGS="$CFLAGS -DNDEBUG" ./configure --prefix="$PREFIX" \
                --disable-shared --enable-static --disable-cpml --disable-frontend --disable-decoder \
                && make -j"$JOBS" && make install) ;;
        libopus)
            autotools "$d" --disable-extra-programs ;;
        libvpx)
            (cd "$d" && ./configure --prefix="$PREFIX" --disable-shared --enable-static --enable-pic \
                --disable-examples --disable-tools --disable-docs --disable-unit-tests \
                --enable-vp9-highbitdepth ${LIBVPX_TARGET:+--target=$LIBVPX_TARGET} \
                && make -j"$JOBS" && make install) ;;
        svtav1)
            (cd "$d" && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
                -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DBUILD_APPS=OFF -DSVT_AV1_LTO=OFF \
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
                && cmake --build build -j "$JOBS" && cmake --install build) ;;
        libogg)
            autotools "$d" --with-pic ;;
        libvorbis)
            autotools "$d" --disable-oggtest ;;
        libtheora)
            autotools "$d" --with-pic --disable-examples --disable-oggtest --disable-vorbistest \
                --disable-spec --disable-doc ;;
        libwebp)
            sed -i '' '/libanim_util/d' "$d/examples/Makefile.am"
            autotools "$d" --with-pic --enable-libwebpmux --enable-libwebpdemux --disable-libwebpextras \
                --disable-sdl --disable-gl --disable-png --disable-jpeg --disable-tiff --disable-gif ;;
        dav1d)
            (cd "$d" && meson setup build --prefix="$PREFIX" --libdir=lib --buildtype=release \
                --default-library=static -Denable_tools=false -Denable_tests=false \
                && ninja -C build -j "$JOBS" && ninja -C build install) ;;
    esac
}

: > "$WORK/pins.txt"
for s in "${LIBS[@]}"; do
    echo "== $s"
    fetch "$s"
    build_lib "$s"
done

echo "== ffmpeg $FFMPEG_TAG"
git clone --quiet --depth 1 --branch "$FFMPEG_TAG" "$FFMPEG_REPO" "$SRC/ffmpeg"
echo "ffmpeg $FFMPEG_REPO $FFMPEG_TAG $(git -C "$SRC/ffmpeg" rev-parse HEAD)" >> "$WORK/pins.txt"
# The configuration of variants/*-knaif.sh, plus each library's --enable as its BtbN stage gives it.
(cd "$SRC/ffmpeg" && ./configure --prefix="$PREFIX" --pkg-config-flags=--static \
    --enable-gpl --disable-debug --disable-autodetect --disable-network --disable-devices \
    --disable-hwaccels --disable-protocols --enable-protocol=file,pipe --disable-ffplay \
    --enable-iconv --enable-zlib --enable-libx264 --enable-libx265 --enable-libmp3lame \
    --enable-libopus --enable-libvpx --enable-libsvtav1 --enable-libvorbis --enable-libtheora \
    --enable-libwebp --enable-libdav1d \
    --extra-cflags="-I$PREFIX/include $CFLAGS" --extra-ldflags="-L$PREFIX/lib $LDFLAGS" \
    --extra-libs="-liconv" --extra-version="$(date -u +%Y%m%d)" \
    && make -j"$JOBS" && make install)

# The pack: bin/, the licence, BUILD.txt; and nothing linked but the system's own libraries.
mkdir -p "$OUT/bin"
cp "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe" "$OUT/bin/"
cp "$SRC/ffmpeg/COPYING.GPLv2" "$OUT/LICENSE.txt"
for b in "$OUT/bin/ffmpeg" "$OUT/bin/ffprobe"; do
    bad=$(otool -L "$b" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)' || true)
    [ -z "$bad" ] || { echo "$b links a non-system library: $bad" >&2; exit 1; }
done
{
    echo "media pack build"
    echo "target:        macos-$ARCH (macOS $MIN_MACOS or newer)"
    echo "ffmpeg:        $FFMPEG_REPO $FFMPEG_TAG (line $LINE)"
    echo "build tooling: native (build-macos.sh); pins from $BTBN_REPO @ $BTBN_COMMIT"
    echo "built:         $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "library source (repository, commit or svn revision):"
    sed 's/^/  /' "$WORK/pins.txt"
} > "$OUT/BUILD.txt"

# The complete corresponding source, as sources.sh makes it for the other platforms.
mkdir -p "$OUT-sources/libraries"
for s in "${LIBS[@]}"; do
    if [ -d "$SRC/$s/.git" ]; then
        git -C "$SRC/$s" archive --format=tar --prefix="$s/" HEAD | xz -T0 > "$OUT-sources/libraries/$s.tar.xz"
    else
        tar -C "$SRC" --exclude=.svn -cJf "$OUT-sources/libraries/$s.tar.xz" "$s"
    fi
done
git -C "$SRC/ffmpeg" archive --format=tar --prefix="ffmpeg-${FFMPEG_TAG#n}/" HEAD | xz -T0 \
    > "$OUT-sources/ffmpeg-${FFMPEG_TAG#n}.tar.xz"
tar -C "$HERE/.." -cJf "$OUT-sources/knaif-runtimes-ffmpeg.tar.xz" "$(basename "$HERE")"
cp "$OUT/BUILD.txt" "$OUT-sources/BUILD.txt"
(cd "$OUT-sources" && find . -type f ! -name SOURCES.txt | sort | xargs shasum -a 256) > "$OUT-sources/SOURCES.txt"
echo "pack: $OUT"
echo "sources: $OUT-sources"
