#!/usr/bin/env bash
# Write NOTICES.txt into a media pack built by build.sh: the licence of every part of the pack,
# with each licence text in full (notices.sh, notices.txt). build.sh runs it as its last step.
#
#   bash ffmpeg/pack-notices.sh <line> <pack-dir> [target]
#     line      9.0 | 8.1 | 7.1   (as given to build.sh)
#     pack-dir  the pack build.sh wrote (NOTICES.txt lands beside LICENSE.txt)
#     target    win64 (default) | linux64, as given to build.sh
#
# The libraries' licence files are read from the build tooling's download cache, the very sources
# that were compiled; ffmpeg's from its pinned tag. A stage the target does not build (the mingw
# runtime on Linux) is left out. No docker needed.
set -euo pipefail

LINE=${1:?usage: pack-notices.sh <line> <pack-dir> [target]}
PACK=${2:?usage: pack-notices.sh <line> <pack-dir> [target]}
TARGET=${3:-win64}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -f "$HERE/variants/$TARGET-knaif.sh" ] || { echo "no variant for $TARGET" >&2; exit 1; }
[ -d "$PACK" ] || { echo "no pack at $PACK" >&2; exit 1; }

# shellcheck source=/dev/null
source <(grep -E '^[A-Z0-9_]+=' "$HERE/PINS")
TAG_VAR="FFMPEG_TAG_${LINE//./_}"
FFMPEG_TAG=${!TAG_VAR:?no ffmpeg tag pinned for line $LINE in PINS}
WORK=${KNAIF_RUNTIMES_WORK:-$HOME/.cache/knaif-runtimes}/btbn-$BTBN_COMMIT
[ -d "$WORK/.cache/downloads" ] || { echo "no build cache at $WORK/.cache/downloads: run build.sh first" >&2; exit 1; }
[ "$(git -C "$WORK" rev-parse HEAD)" = "$BTBN_COMMIT" ] || { echo "$WORK is not at $BTBN_COMMIT" >&2; exit 1; }
# shellcheck source=btbn.sh
source "$HERE/btbn.sh"
# shellcheck source=notices.sh
source "$HERE/notices.sh"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
git clone --quiet --depth 1 --branch "$FFMPEG_TAG" "$FFMPEG_REPO" "$tmp/ffmpeg"
sources=("ffmpeg=$tmp/ffmpeg")

mapfile -t KEEP < <(grep -v -E '^\s*(#|$)' "$HERE/allowlist.txt")
for s in "${KEEP[@]}"; do
    mapfile -t scripts < <(btbn_stage_scripts "$s")
    [ "${#scripts[@]}" -gt 0 ] || { echo "allowlist names $s, which has no stage at $BTBN_COMMIT" >&2; exit 1; }
    for f in "${scripts[@]}"; do
        btbn_stage_enabled "$f" || continue   # not built for this target (mingw on Linux)
        archive=$(btbn_stage_archive "$f")
        [ -n "$archive" ] || continue   # a stage with nothing to download (e.g. base)
        sources+=("$s=$archive")
    done
done

write_notices "$PACK/NOTICES.txt" "media pack, ffmpeg $FFMPEG_TAG, $TARGET" "${sources[@]}"
echo "notices: $PACK/NOTICES.txt"
