# Third-party notices

The root MIT license applies to Still Music's original files, not to third-party code.

| Dependency | Use | License and source |
| --- | --- | --- |
| TagLib 2.2.1 | Embedded lyrics metadata editing, statically linked | [MPL 1.1 option](Vendor/taglib-2.2.1/COPYING.MPL); [complete vendored source](Vendor/taglib-2.2.1); [provenance and checksum](Vendor/README.md) |
| utfcpp (bundled with TagLib) | Unicode conversion | [Boost Software License 1.0](Vendor/taglib-2.2.1/3rdparty/utfcpp/LICENSE) |

The build copies these license texts, this notice and Still Music's MIT license into the app's Resources directory. Keep the full vendored source and its original notices available with source distributions. TagLib is unmodified; do not relabel its files as MIT.

Apple frameworks and system fonts are provided by macOS and are not copied into this repository. The icon is drawn by `scripts/make-icon.swift`; no third-party icon font is bundled.
