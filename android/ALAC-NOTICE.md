# ALAC decoder

The packet decoder core (`AlacFile.java`, `LeadingZeros.java`) comes from
https://github.com/umjammer/vavi-sound-alac at commit
`fd221243f01cd1ab54a55ca1fe08f5fb3323e62b`, derived from Peter McQuillan's Java Apple
Lossless decoder and David Hammerton's ALAC decoder. It is BSD-licensed; the full
notice is included in the APK at `assets/licenses/alac-BSD.txt`.

Local adaptations remove desktop-only logging, reject unsupported prediction
types instead of logging and continuing, bound frame/channel/sample sizes, and
remove a redundant aliased-array copy in zero-order prediction.
The packet adapter and Media3 renderer support 16/24-bit mono/stereo ALAC with
up to 16384 frames per packet. They output 16-bit integer PCM, matching Still's
existing compatibility path. This does not claim bit-perfect 24-bit output.
No Java Sound, MP4 demuxer, or native libraries from that project are bundled.

Regression fixtures are generated tones using Python's WAV writer and macOS
`afconvert`, with packet data extracted from the generated MP4 sample tables.
They contain no third-party music.
