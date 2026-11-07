# Third-party notices

The root MIT license applies to Still Music's original files, not to third-party code.

| Dependency | Use | License and source |
| --- | --- | --- |
| TagLib 2.2.1 | Embedded lyrics metadata editing, statically linked | [MPL 1.1 option](Vendor/taglib-2.2.1/COPYING.MPL); [complete vendored source](Vendor/taglib-2.2.1); [provenance and checksum](Vendor/README.md) |
| utfcpp (bundled with TagLib) | Unicode conversion | [Boost Software License 1.0](Vendor/taglib-2.2.1/3rdparty/utfcpp/LICENSE) |

The build copies these license texts, this notice and Still Music's MIT license into the app's Resources directory. Keep the full vendored source and its original notices available with source distributions. TagLib is unmodified; do not relabel its files as MIT.

Apple frameworks and system fonts are provided by macOS and are not copied into this repository. The icon is drawn by `scripts/make-icon.swift`; no third-party icon font is bundled.

## FFmpeg 8.0.1

The separate StillDecoder executable is built from unmodified FFmpeg 8.0.1 under LGPL 2.1-or-later, with GPL, nonfree components, network protocols and external libraries disabled. Source archive: `Vendor/ffmpeg/ffmpeg-8.0.1.tar.xz`; upstream: https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz. SHA-256: `05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41`.

The complete corresponding source archive, license text and build script are also distributed inside the app under `Contents/Resources/ThirdPartyLicenses`. To rebuild or modify the decoder, extract the source archive and use the configure/make commands in `scripts/build-decoder.sh`; replace `Contents/MacOS/StillDecoder` with your build and re-sign your local app. Still's MIT license does not replace FFmpeg's license.
