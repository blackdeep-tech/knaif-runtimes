# shellcheck shell=bash
# The media pack's third-party notices (NOTICES.txt): the licence of every part of the pack, with
# each licence text in full. The pack as a whole is GPL (LICENSE.txt), but the libraries inside it
# keep their own licences, and most of those ask that a binary carry their notices.
#
# Sourced by pack-notices.sh (Windows and Linux) and build-macos.sh; written for macOS's own
# /bin/bash 3.2 (no `mapfile`, no associative arrays, no `source <(...)`).
#
#   write_notices <out-file> <title> <stage>=<source> ...
#     source  the stage's source tree (a folder), or its source archive (.tar.xz whose members are
#             named ./<path>, as in the build tooling's download cache)
#
# notices.txt names each stage's licence and licence files. Nothing is written, and the call fails,
# when a stage given has no line there, when a file the line names is missing from the source, or
# when allowlist.txt keeps a stage that has no line (so a stage added to the build cannot ship
# without its notices). A stage whose line says "-" is not part of the pack and is skipped.

NOTICES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NOTICES_LIST=${NOTICES_LIST:-$NOTICES_DIR/notices.txt}
NOTICES_ALLOWLIST=${NOTICES_ALLOWLIST:-$NOTICES_DIR/allowlist.txt}

# "<licence>|<files>" for a stage, from notices.txt; nothing when it has no line.
notices_line() {  # stage
    awk -F'|' -v s="$1" '
        function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
        /^[ \t]*(#|$)/ { next }
        trim($1) == s { print trim($2) "|" trim($3); exit }
    ' "$NOTICES_LIST"
}

# notices.txt is well formed and has a line for every stage allowlist.txt keeps.
notices_check() {
    local bad s
    bad=$(awk -F'|' '
        function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
        /^[ \t]*(#|$)/ { next }
        NF != 3 || trim($1) == "" || trim($2) == "" || trim($3) == "" ||
            ((trim($2) == "-") != (trim($3) == "-")) { print NR ": " $0 }
    ' "$NOTICES_LIST")
    [ -z "$bad" ] || { echo "notices.txt: malformed line $bad" >&2; return 1; }
    while IFS= read -r s; do
        [ -n "$(notices_line "$s")" ] \
            || { echo "notices.txt has no line for $s, which allowlist.txt keeps" >&2; return 1; }
    done < <(grep -v -E '^[[:space:]]*(#|$)' "$NOTICES_ALLOWLIST" | tr -d '\r' | sed 's/[[:space:]]*$//')
}

# Print one file of a stage's source to stdout; fail when it is not there.
notices_cat() {  # source path
    if [ -d "$1" ]; then
        [ -f "$1/$2" ] && cat "$1/$2"
    elif [ -f "$1" ]; then
        tar -xOJf "$1" "./$2" 2>/dev/null || tar -xOJf "$1" "$2" 2>/dev/null
    else
        return 1
    fi
}

write_notices() {  # out-file title stage=source...
    local out=$1 title=$2
    shift 2
    notices_check || return 1
    local tmp pair stage src line licence files f rule
    tmp=$(mktemp -d) || return 1
    rule=$(printf '%080d' 0 | tr 0 =)
    : > "$tmp/index"
    : > "$tmp/texts"
    for pair in "$@"; do
        stage=${pair%%=*}
        src=${pair#*=}
        line=$(notices_line "$stage")
        [ -n "$line" ] || { echo "notices.txt has no line for $stage" >&2; rm -rf -- "$tmp"; return 1; }
        licence=${line%%|*}
        files=${line#*|}
        [ "$files" = "-" ] && continue
        [ -e "$src" ] || { echo "no source for $stage at $src" >&2; rm -rf -- "$tmp"; return 1; }
        printf '  %-18s %s\n' "$stage" "$licence" >> "$tmp/index"
        printf '\n%s\n%s: %s\n%s\n' "$rule" "$stage" "$licence" "$rule" >> "$tmp/texts"
        for f in $files; do
            printf '\n--- %s/%s\n\n' "$stage" "$f" >> "$tmp/texts"
            notices_cat "$src" "$f" >> "$tmp/texts" \
                || { echo "$stage: no $f in $src" >&2; rm -rf -- "$tmp"; return 1; }
        done
    done
    {
        echo "Third-party notices: $title"
        echo
        echo "This media pack is distributed under the GNU General Public License, version 2 or later"
        echo "(LICENSE.txt), because it includes x264 and x265. It is built from the components"
        echo "below; each keeps its own licence, and its licence texts follow in full. BUILD.txt names"
        echo "the source commit of each. The complete corresponding source of this build is"
        echo "published beside the pack."
        echo
        cat "$tmp/index"
        cat "$tmp/texts"
    } > "$tmp/NOTICES.txt" && mv -f "$tmp/NOTICES.txt" "$out"
    local rc=$?
    rm -rf -- "$tmp"
    return $rc
}
