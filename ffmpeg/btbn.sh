# shellcheck shell=bash
# The build tooling's stages, as sources.sh and pack-notices.sh need them: which stage scripts make
# up a kept stage, whether one builds for the target, and the cached source archive it compiled.
# Sourced after WORK (the tooling's checkout at BTBN_COMMIT), TARGET and LINE are set.
#
# Each cached archive is named after the sha256 of the download command its stage pins (repository
# and commit); btbn_stage_archive recomputes that name from the stage script, so what it returns is
# the very source that was compiled.

CACHE=$WORK/.cache/downloads

# The stage scripts of a kept stage: scripts.d/NN-<name>.sh, or the scripts in scripts.d/NN-<name>/.
btbn_stage_scripts() {  # stage
    local f
    for f in "$WORK"/scripts.d/??-"$1".sh "$WORK"/scripts.d/??-"$1"/*.sh; do
        [ -f "$f" ] && echo "$f"
    done
}

# The download command a stage pins, exactly as the tooling's download.sh computes it.
btbn_stage_dl() {  # stage-script
    (
        set +eu
        # shellcheck source=/dev/null
        source "$WORK/util/dl_functions.sh"
        # shellcheck source=/dev/null
        source "$1"
        ffbuild_dockerdl
    )
}

# Whether a stage builds for $TARGET and the line: its own `ffbuild_enabled`, as the tooling asks
# it. Some stages ask which ffmpeg they build for (`ffbuild_ffver`, from the line's add-in), so
# that one function is taken from the tooling's util/vars.sh, which cannot be sourced whole.
BTBN_FFVER_FN=$(sed -n '/^ffbuild_ffver() {/,/^}/p' "$WORK/util/vars.sh")
[ -n "$BTBN_FFVER_FN" ] || { echo "no ffbuild_ffver in $WORK/util/vars.sh" >&2; exit 1; }
btbn_stage_enabled() {  # stage-script
    (
        set +eu
        # shellcheck disable=SC2034  # read by the stage script sourced below
        TARGET=$TARGET VARIANT=knaif ADDINS_STR=$LINE
        eval "$BTBN_FFVER_FN"
        # shellcheck source=/dev/null
        source "$WORK/util/dl_functions.sh"
        # shellcheck source=/dev/null
        source "$1"
        ffbuild_enabled
    )
}

# The cached source archive a stage script compiled; nothing for a stage with nothing to download
# (e.g. base). Fails when the archive is missing (the build did not run, or ran other sources).
btbn_stage_archive() {  # stage-script
    local stg name hash archive
    stg=$(btbn_stage_dl "$1")
    [ -n "$stg" ] || return 0
    name=$(basename "$1" .sh)
    hash=$(sha256sum <<<"$stg" | cut -d' ' -f1)
    archive="$CACHE/${name}_${hash}.tar.xz"
    [ -f "$archive" ] || { echo "no cached source for $name ($archive): rebuild" >&2; return 1; }
    echo "$archive"
}
