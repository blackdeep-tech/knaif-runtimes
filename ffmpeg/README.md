# The media pack: knaif's own ffmpeg

A reduced, static build of `ffmpeg` and `ffprobe` that knaif runs as a separate program, found
before any ffmpeg on `PATH`. It exists so that media skills work on a PC where the user installed
nothing, including Windows with Smart App Control on, where an unsigned ffmpeg is blocked.

## What it contains

- **Writes only what the recipes use.** The libraries are the ones in `allowlist.txt`: x264,
  x265, LAME, Opus, libvpx, SVT-AV1, Ogg/Vorbis, Theora, WebP, and dav1d for AV1 input.
  knaif's `contracts/runtimes/media.capabilities.yaml` lists the encoders, filters and output formats the
  media engine can name; a test fails when the engine names something that list lacks, and checks
  a built pack against it (knaif's `toolkits/media` tests, with `KNAIF_MEDIA_PACK_BIN=<pack>/bin`).
- **Reads any common file.** Decoders and demuxers stay ffmpeg's native set.
- **Local files only, the same result on every machine.** No network protocols (only `file` and
  `pipe`), no capture devices, no hardware acceleration.
- **Licence:** the build enables GPL components (x264, x265), so the pack is distributed under the
  GPL, version 2 or later, with its source. knaif runs it as a separate program and is not a
  combined work with it.

## Building

```bash
bash ffmpeg/build.sh <line> <out-dir> [target]   # line: 9.0 | 8.1 | 7.1; target: win64 | linux64
```

Linux with docker; on Windows, inside WSL with Docker Desktop's WSL integration on. The build
tooling is BtbN's FFmpeg-Builds at the commit in `PINS`: it cross-builds every library from the
source commit its stage script pins, in docker. `build.sh` switches off every stage not on the
allowlist, adds the variant in `variants/`, and builds ffmpeg at the release tag `PINS` names for
the line. The pack lands in `<out-dir>` with `BUILD.txt` (every pinned version) and the licence.
The tooling's checkout and download cache live in `$KNAIF_RUNTIMES_WORK` (default
`~/.cache/knaif-runtimes`), never in the repository.

## Sources

```bash
bash ffmpeg/sources.sh <line> <out-dir>   # after build.sh, on the same machine
```

The pack is GPL, so each published pack goes out with its complete corresponding source:
`ffmpeg-<version>.tar.xz` (ffmpeg at the pinned tag), `libraries/<stage>.tar.xz` (every linked
library's source, copied from the build tooling's download cache, so they are the bytes that were
compiled), `FFmpeg-Builds-<commit>.tar.xz` (the tooling) and `knaif-runtimes-ffmpeg.tar.xz` (this
folder). `SOURCES.txt` lists each file's sha256 and origin. The script recomputes each library
archive's name from the download command its stage pins, and stops when one is missing.
