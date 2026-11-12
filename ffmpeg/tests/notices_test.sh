#!/usr/bin/env bash
# Tests for notices.sh, the media pack's third-party notices. No build, docker or network needed.
#
#   bash ffmpeg/tests/notices_test.sh
#
# Fixtures are small fake source trees and one .tar.xz shaped like the build tooling's download
# cache (members named ./<path>). The last test reads the real notices.txt and allowlist.txt.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB=$HERE/../notices.sh
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1" >&2; fails=$((fails + 1)); }

mkdir -p "$T/src/alpha" "$T/src/beta/sub" "$T/arch/gamma" "$T/arch/empty"
echo "alpha licence text" > "$T/src/alpha/COPYING"
echo "beta main licence" > "$T/src/beta/LICENSE"
echo "beta third-party licence" > "$T/src/beta/sub/LICENSE"
echo "gamma licence text" > "$T/arch/gamma/COPYING"
echo "not a licence" > "$T/arch/empty/README"
tar -C "$T/arch/gamma" -cJf "$T/gamma.tar.xz" .
tar -C "$T/arch/empty" -cJf "$T/empty.tar.xz" .
cat > "$T/list" <<'EOF'
# stage | licence | licence files in its source
alpha | GPL-2.0-or-later | COPYING
beta  | BSD-3-Clause     | LICENSE sub/LICENSE

gamma | MIT              | COPYING
tools | -                | -
EOF
printf 'alpha\nbeta\n# a comment\ngamma\ntools\n' > "$T/allow"

# write_notices with the fixture list and allowlist; stderr goes to $T/err.
run() {
    (
        # shellcheck disable=SC2034  # read by notices.sh, sourced below
        NOTICES_LIST=$T/list
        # shellcheck disable=SC2034
        NOTICES_ALLOWLIST=${ALLOW:-$T/allow}
        # shellcheck source=../notices.sh
        source "$LIB"
        write_notices "$@"
    ) 2> "$T/err"
}

# 1. Every listed file's full text lands in the notices, from folders and from archives.
if run "$T/out1" "test pack" alpha="$T/src/alpha" beta="$T/src/beta" gamma="$T/gamma.tar.xz" \
    && grep -q "alpha licence text" "$T/out1" \
    && grep -q "beta main licence" "$T/out1" \
    && grep -q "beta third-party licence" "$T/out1" \
    && grep -q "gamma licence text" "$T/out1" \
    && grep -q "test pack" "$T/out1" \
    && grep -q "sub/LICENSE" "$T/out1"; then
    ok "writes every listed licence text, from a folder and from an archive"
else
    bad "writes every listed licence text ($(cat "$T/err"))"
fi

# 2. The index names each component with its licence, in the order given.
if grep -E -q '^  alpha +GPL-2.0-or-later$' "$T/out1" \
    && grep -E -q '^  gamma +MIT$' "$T/out1" \
    && [ "$(grep -n -E '^  (alpha|beta|gamma) ' "$T/out1" | cut -d: -f2 | awk '{print $1}' | tr '\n' ' ')" = "alpha beta gamma " ]; then
    ok "index lists each component and its licence, in order"
else
    bad "index lists each component and its licence"
fi

# 3. A build-only stage ("-") is accepted and left out of the notices.
if run "$T/out3" "test pack" alpha="$T/src/alpha" tools="$T/src/beta" \
    && ! grep -q -E '^  tools ' "$T/out3" && ! grep -q "beta main licence" "$T/out3"; then
    ok "a build-only stage is left out"
else
    bad "a build-only stage is left out ($(cat "$T/err"))"
fi

# 4. A listed file missing from a folder fails, names the file, and writes nothing.
mkdir -p "$T/src/beta-half"
cp "$T/src/beta/LICENSE" "$T/src/beta-half/"
if ! run "$T/out4" "test pack" alpha="$T/src/alpha" beta="$T/src/beta-half" \
    && [ ! -e "$T/out4" ] && grep -q "sub/LICENSE" "$T/err" && grep -q "beta" "$T/err"; then
    ok "a missing licence file in a folder fails and writes nothing"
else
    bad "a missing licence file in a folder fails and writes nothing"
fi

# 5. A listed file missing from an archive fails the same way.
if ! run "$T/out5" "test pack" gamma="$T/empty.tar.xz" \
    && [ ! -e "$T/out5" ] && grep -q "COPYING" "$T/err" && grep -q "gamma" "$T/err"; then
    ok "a missing licence file in an archive fails and writes nothing"
else
    bad "a missing licence file in an archive fails and writes nothing"
fi

# 6. A stage the list does not know fails.
if ! run "$T/out6" "test pack" delta="$T/src/alpha" && [ ! -e "$T/out6" ] && grep -q "delta" "$T/err"; then
    ok "a stage with no line in the list fails"
else
    bad "a stage with no line in the list fails"
fi

# 7. A stage the allowlist keeps but the list does not know fails, even when it is not given.
cp "$T/allow" "$T/allow7"
echo "epsilon" >> "$T/allow7"
if ! ALLOW=$T/allow7 run "$T/out7" "test pack" alpha="$T/src/alpha" \
    && [ ! -e "$T/out7" ] && grep -q "epsilon" "$T/err"; then
    ok "an allowlist stage with no line in the list fails"
else
    bad "an allowlist stage with no line in the list fails"
fi

# 8. A source that is neither a folder nor an archive fails.
if ! run "$T/out8" "test pack" alpha="$T/nowhere" && [ ! -e "$T/out8" ] && grep -q "nowhere" "$T/err"; then
    ok "a missing source fails"
else
    bad "a missing source fails"
fi

# 9. The real list: a line for every stage the real allowlist keeps and for ffmpeg itself, each
#    with a licence and files (or "-" for both).
if (
    unset NOTICES_LIST NOTICES_ALLOWLIST
    # shellcheck source=../notices.sh
    source "$LIB"
    notices_check && [ -n "$(notices_line ffmpeg)" ]
) 2> "$T/err"; then
    ok "the real notices.txt covers allowlist.txt and ffmpeg"
else
    bad "the real notices.txt covers allowlist.txt and ffmpeg ($(cat "$T/err"))"
fi

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed" >&2; exit 1; }
