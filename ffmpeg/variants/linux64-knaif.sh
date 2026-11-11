#!/bin/bash
# The media pack's variant for 64-bit Linux: the win64 variant's reduced GPL configuration, packaged
# as a static Linux build. The libraries come from the stages in allowlist.txt (the mingw stages
# switch themselves off on Linux); no network, capture devices or hardware acceleration, so a
# result never depends on the machine it runs on and the program reads and writes local files only.
source "$(dirname "$BASH_SOURCE")"/linux-install-static.sh
FF_CONFIGURE="--enable-gpl --disable-debug --disable-autodetect --disable-network \
--disable-devices --disable-hwaccels --disable-protocols --enable-protocol=file,pipe \
--disable-ffplay"
# As on Windows: nothing on this short list brings `-liconv` to the link through pkg-config.
FF_LIBS="-liconv"
FF_CFLAGS=""
FF_CXXFLAGS=""
FF_LDFLAGS=""
GIT_BRANCH="master"
LICENSE_FILE="COPYING.GPLv2"
