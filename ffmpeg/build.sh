#!/usr/bin/env bash
# Build the media pack: a reduced, static GPL ffmpeg/ffprobe for one target, from pinned sources.
#
#   bash ffmpeg/build.sh <line> <out-dir> [target]
#     line     9.0 | 8.1 | 7.1      (the ffmpeg release line; the exact tag is in PINS)
#     out-dir  where the pack lands (bin/, doc/, LICENSE.txt, NOTICES.txt, BUILD.txt)
#     target   win64 (default) | linux64
#
# Runs on Linux with docker (on Windows: inside WSL with Docker Desktop's WSL integration on).
# It uses BtbN's FFmpeg-Builds at the commit in PINS: that tooling cross-builds every library from
# the source commit its stage script pins, in docker. This script switches off every stage not in
# allowlist.txt, adds the knaif variant (variants/), and builds ffmpeg at the pinned release tag.
# Last, pack-notices.sh writes NOTICES.txt: every library's licence texts, from the compiled sources.
# The tooling checkout and its download cache live in $KNAIF_RUNTIMES_WORK (default
# ~/.cache/knaif-runtimes), never in the repository.
set -euo pipefail

LINE=${1:?usage: build.sh <line> <out-dir> [target]}
OUT_ARG=${2:?usage: build.sh <line> <out-dir> [target]}
TARGET=${3:-win64}
VARIANT=knaif
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$OUT_ARG"
OUT=$(cd "$OUT_ARG" && pwd)

# shellcheck source=/dev/null
source <(grep -E '^[A-Z0-9_]+=' "$HERE/PINS")
TAG_VAR="FFMPEG_TAG_${LINE//./_}"
FFMPEG_TAG=${!TAG_VAR:?no ffmpeg tag pinned for line $LINE in PINS}
[ -f "$HERE/variants/$TARGET-$VARIANT.sh" ] || { echo "no variant for $TARGET" >&2; exit 1; }

WORK=${KNAIF_RUNTIMES_WORK:-$HOME/.cache/knaif-runtimes}/btbn-$BTBN_COMMIT
if [ ! -d "$WORK/.git" ]; then
    git clone --quiet "$BTBN_REPO" "$WORK"
fi
git -C "$WORK" fetch --quiet origin "$BTBN_COMMIT" 2>/dev/null || true
git -C "$WORK" checkout --quiet --force "$BTBN_COMMIT"
git -C "$WORK" clean --quiet -fdx -e .cache   # back to the pinned tree; keep the download cache
cp "$HERE/variants/$TARGET-$VARIANT.sh" "$WORK/variants/"

# Switch off every stage that is not on the allowlist (a stage is scripts.d/NN-<name>.sh or a
# folder scripts.d/NN-<name>/). A disabled stage downloads and builds nothing, and contributes
# its `--disable-...` to ffmpeg's configure instead of its `--enable-...`. (The tooling's
# download step fetches every stage's source without asking whether the stage is enabled, so
# the download hook is emptied as well.)
mapfile -t KEEP < <(grep -v -E '^\s*(#|$)' "$HERE/allowlist.txt")
keep() { local s; for s in "${KEEP[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }
disabled=()
for path in "$WORK"/scripts.d/*; do
    name=$(basename "$path" .sh)
    name=${name#??-}
    case "$name" in final) continue ;; esac
    keep "$name" && continue
    if [ -d "$path" ]; then files=("$path"/*.sh); else files=("$path"); fi
    for f in "${files[@]}"; do
        printf '\nffbuild_enabled() { return -1; }\nffbuild_dockerdl() { :; }\n' >> "$f"
    done
    disabled+=("$name")
done
echo "stages kept: ${KEEP[*]}"
echo "stages switched off: ${#disabled[@]}"

cd "$WORK"
# Keep the docker builder between builds: removing it after each image (the tooling's default)
# made every line rebuild the cross toolchain (25 min each, 2026-11-11).
NOCLEAN=1 ./makeimage.sh "$TARGET" "$VARIANT" "$LINE"
FFMPEG_REPO_OVERRIDE="$FFMPEG_REPO" GIT_BRANCH_OVERRIDE="$FFMPEG_TAG" FFBUILD_OUTPUT_DIR="$OUT" \
    ./build.sh "$TARGET" "$VARIANT" "$LINE"

{
    echo "media pack build"
    echo "target:        $TARGET"
    echo "ffmpeg:        $FFMPEG_REPO $FFMPEG_TAG (line $LINE)"
    echo "build tooling: $BTBN_REPO @ $BTBN_COMMIT"
    echo "stages kept:   ${KEEP[*]}"
    echo "built:         $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "library source commits (SCRIPT_COMMIT of each kept stage):"
    for s in "${KEEP[@]}"; do
        for f in "$WORK"/scripts.d/??-"$s".sh "$WORK"/scripts.d/??-"$s"/*.sh; do
            [ -f "$f" ] || continue
            c=$(grep -m1 -E '^SCRIPT_(COMMIT|TAG|REV)=' "$f" || true)
            r=$(grep -m1 -E '^SCRIPT_(REPO|URL)=' "$f" || true)
            [ -n "$c$r" ] && echo "  $s: ${r#*=} ${c#*=}"
        done
    done
} > "$OUT/BUILD.txt"
bash "$HERE/pack-notices.sh" "$LINE" "$OUT" "$TARGET"
echo "pack: $OUT"
