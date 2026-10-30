# Demo mode assets

These files are fake chat content for the `FLUFFYGRAM_DEMO` build flag (see `docs/BUILD.md`). They
are not user content and never travel over Matrix: the demo seed resolves `mxc://fluffygram.local/...`
to these bundled assets. Nothing here identifies a real person.

| Directory | Files | Source | Licence |
| --- | --- | --- | --- |
| `photo/` | 10 JPG, 1024x768 or 768x1024 | Lorem Picsum (`https://picsum.photos/seed/<name>/...`), the seed name is in each filename | Unsplash licence, served by Lorem Picsum |
| `thumb/` | 11 JPG, 240x240 square crops of `photo/` plus `clip_01.jpg` (a frame of `video/clip_01.mp4`) | derived locally with ImageMagick / ffmpeg | same as the source |
| `sticker/` | 6 PNG, 256x256 RGBA (`1f44d` thumbs up, `1f602` tears of joy, `1f525` fire, `1f389` party popper, `1f431` cat, `1f6f8` flying saucer) | Twemoji `assets/svg/<codepoint>.svg`, rendered with `rsvg-convert` | graphics (c) Twitter, Inc. and other contributors, CC-BY 4.0 |
| `voice/` | 4 WAV, 16 kHz mono, 6.0 s to 7.7 s | synthesised locally with Qwen3-TTS from the text of each line | no third-party rights involved |
| `video/` | 1 MP4, 3 s, 480x854, 200 KB | generated locally with ffmpeg's `testsrc2` source | no third-party rights involved |

Total 2.7 MB. Every build (demo and production) carries them, because Flutter asset lists are not
build-conditional.

Twemoji attribution, as required by CC-BY 4.0: "Twitter, Inc." and
[contributors](https://github.com/twitter/twemoji/graphs/contributors),
used under [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/). No modifications beyond
vector-to-raster rendering at 256 px.
