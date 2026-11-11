#!/usr/bin/env bash
# Gather the complete corresponding source of a media pack built by build.sh, for the GPL: ffmpeg
# at the pinned tag, the source of every library linked into it, and the scripts that built it.
#
#   bash ffmpeg/sources.sh <line> <out-dir>
#     line     9.0 | 8.1 | 7.1   (as given to build.sh)
#     out-dir  where the source set lands (one .tar.xz per part, plus SOURCES.txt with sha256s)
#
# Runs where build.sh ran (Linux, or WSL on Windows), after it: the libraries' sources are taken
# from the build tooling's own download cache, so they are the very bytes that were compiled. Each
# cached archive is named after the sha256 of the download command its stage pins (repository and
# commit); this script recomputes that name from the stage script and refuses a library whose
# archive is missing, so a source set never silently differs from the build. No docker needed.
set -euo pipefail

LINE=${1:?usage: sources.sh <line> <out-dir>}
OUT_ARG=${2:?usage: sources.sh <line> <out-dir>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$OUT_ARG"
OUT=$(cd "$OUT_ARG" && pwd)

# shellcheck source=/dev/null
source <(grep -E '^[A-Z0-9_]+=' "$HERE/PINS")
TAG_VAR="FFMPEG_TAG_${LINE//./_}"
FFMPEG_TAG=${!TAG_VAR:?no ffmpeg tag pinned for line $LINE in PINS}
WORK=${KNAIF_RUNTIMES_WORK:-$HOME/.cache/knaif-runtimes}/btbn-$BTBN_COMMIT
CACHE=$WORK/.cache/downloads
[ -d "$CACHE" ] || { echo "no build cache at $CACHE: run build.sh first" >&2; exit 1; }
[ "$(git -C "$WORK" rev-parse HEAD)" = "$BTBN_COMMIT" ] || { echo "$WORK is not at $BTBN_COMMIT" >&2; exit 1; }

mapfile -t KEEP < <(grep -v -E '^\s*(#|$)' "$HERE/allowlist.txt")
mkdir -p "$OUT/libraries"
manifest=()

# The download command a stage pins, exactly as the tooling's download.sh computes it.
stage_dl() {  # stage-script
    (
        set +eu
        # shellcheck source=/dev/null
        source "$WORK/util/dl_functions.sh"
        # shellcheck source=/dev/null
        source "$1"
        ffbuild_dockerdl
    )
}

for s in "${KEEP[@]}"; do
    found=0
    for f in "$WORK"/scripts.d/??-"$s".sh "$WORK"/scripts.d/??-"$s"/*.sh; do
        [ -f "$f" ] || continue
        found=1
        stg=$(stage_dl "$f")
        [ -n "$stg" ] || continue   # a stage with nothing to download (e.g. base)
        name=$(basename "$f" .sh)
        hash=$(sha256sum <<<"$stg" | cut -d' ' -f1)
        archive="$CACHE/${name}_${hash}.tar.xz"
        [ -f "$archive" ] || { echo "no cached source for $name ($archive): rebuild" >&2; exit 1; }
        cp "$archive" "$OUT/libraries/$name.tar.xz"
        manifest+=("libraries/$name.tar.xz|$stg")
    done
    [ "$found" = 1 ] || { echo "allowlist names $s, which has no stage at $BTBN_COMMIT" >&2; exit 1; }
done

# ffmpeg itself, at the pinned tag.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
git clone --quiet --depth 1 --branch "$FFMPEG_TAG" "$FFMPEG_REPO" "$tmp/ffmpeg"
git -C "$tmp/ffmpeg" archive --format=tar --prefix="ffmpeg-${FFMPEG_TAG#n}/" HEAD \
    | xz -T0 > "$OUT/ffmpeg-${FFMPEG_TAG#n}.tar.xz"
manifest+=("ffmpeg-${FFMPEG_TAG#n}.tar.xz|$FFMPEG_REPO $FFMPEG_TAG $(git -C "$tmp/ffmpeg" rev-parse HEAD)")

# The build scripts: the tooling at its commit, and knaif's own part (this folder).
git -C "$WORK" archive --format=tar --prefix="FFmpeg-Builds-$BTBN_COMMIT/" "$BTBN_COMMIT" \
    | xz -T0 > "$OUT/FFmpeg-Builds-$BTBN_COMMIT.tar.xz"
manifest+=("FFmpeg-Builds-$BTBN_COMMIT.tar.xz|$BTBN_REPO $BTBN_COMMIT")
tar -C "$HERE/.." -cJf "$OUT/knaif-runtimes-ffmpeg.tar.xz" "$(basename "$HERE")"
manifest+=("knaif-runtimes-ffmpeg.tar.xz|the knaif build files: build.sh, PINS, allowlist.txt, variants/")

{
    echo "media pack source set"
    echo "ffmpeg:        $FFMPEG_TAG (line $LINE)"
    echo "build tooling: $BTBN_REPO @ $BTBN_COMMIT"
    echo "gathered:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "To rebuild: unpack FFmpeg-Builds and knaif-runtimes-ffmpeg, then follow"
    echo "ffmpeg/README.md (build.sh switches off every stage not in allowlist.txt and builds"
    echo "ffmpeg at the tag above). Each library archive is the source its stage downloads."
    echo
    echo "sha256  file  (origin)"
    for m in "${manifest[@]}"; do
        file=${m%%|*}
        echo "$(sha256sum "$OUT/$file" | cut -d' ' -f1)  $file  (${m#*|})"
    done
} > "$OUT/SOURCES.txt"
echo "sources: $OUT"
