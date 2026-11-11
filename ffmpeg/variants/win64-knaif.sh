#!/bin/bash
# The media pack's variant: a static win64 GPL build. The libraries come from the stages in
# allowlist.txt (each enables its own `--enable-lib...`); the rest of the build is ffmpeg's own
# native components, without network, capture devices or hardware acceleration, so a result
# never depends on the machine it runs on and the program reads and writes local files only.
source "$(dirname "$BASH_SOURCE")"/windows-install-static.sh
FF_CONFIGURE="--enable-gpl --disable-debug --disable-autodetect --disable-network \
--disable-devices --disable-hwaccels --disable-protocols --enable-protocol=file,pipe \
--disable-ffplay"
# ffmpeg enables iconv (the libiconv stage), but nothing else on this short list brings `-liconv`
# to the link the way the full builds' libraries do through their pkg-config files.
FF_LIBS="-liconv"
FF_CFLAGS=""
FF_CXXFLAGS=""
FF_LDFLAGS=""
GIT_BRANCH="master"
LICENSE_FILE="COPYING.GPLv2"
