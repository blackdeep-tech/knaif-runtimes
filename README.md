# knaif-runtimes

The third-party programs [knaif](https://github.com/blackdeep-tech/knaif) ships itself, so that its
skills work on a computer where the user installed nothing else. Each program has a folder here
with the scripts that build it from pinned sources, and a tag namespace for its releases
(`ffmpeg/<version>`).

| Folder | Program | Used by |
|---|---|---|
| [`ffmpeg/`](ffmpeg/README.md) | the media engine: a reduced, static FFmpeg and ffprobe | knaif's media skills |

knaif runs these programs as separate processes; it does not link to them. knaif installs a
program into its runtime store (`~/.knaif/runtimes/<name>/<version>/`) from a signed runtime
manifest that lists every file's sha256, and finds it there before any copy on `PATH`. The
manifest, the version each knaif release pins and the resolution order live in knaif's
`contracts/runtimes/`.

## Licences

The scripts in this repository are licensed under the Apache License 2.0 (`LICENSE`). The programs
they build keep their own licences: the media engine includes x264 and x265 and is therefore
distributed under the GNU General Public License, version 2 or later. Every published build carries
that licence (`LICENSE.txt`) and the licence texts of every library inside it (`NOTICES.txt`), and
goes out with its complete corresponding source (the program at its tag, the source of every
library linked into it, and these build scripts), listed with sha256s in its `SOURCES.txt`.
