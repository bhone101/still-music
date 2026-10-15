# Contributing

This repository currently accepts changes to the macOS app. Please keep pull requests focused and explain the user-visible problem they solve. Discuss substantial feature or architecture changes in an issue first.

## Setup

Follow the [build instructions](README.md#build-and-run). Swift Package Manager describes the Swift targets; the scripts build the bundled C++ TagLib dependency first.

Run `bash scripts/check.sh` and `bash scripts/build-app.sh` before submitting a code change. For UI changes, also check light/dark themes, narrow windows, larger text and keyboard navigation. Include screenshots made with generated or appropriately licensed sample media, not private library data.

## Code conventions

- Use the surrounding Swift style: four-space indentation, descriptive names, small helpers and explicit error handling around IO.
- Keep reusable parsing, queue and storage behavior in `StillCore`; SwiftUI and AppKit interaction belong in `Sources/Still`.
- Avoid blocking the main actor with file scans, artwork decoding or network requests.
- Preserve existing library compatibility, user preferences and original audio data.
- Add focused regression checks for behavior changes. Do not add tests that simply repeat implementation details.
- Do not change vendored source or dependency versions incidentally. Document provenance and license changes when updating dependencies.

## Reports and pull requests

Include macOS version, CPU architecture, app version, expected/actual behavior and reproduction steps. Audio reports should include container/codec, sample rate, bit depth and output route when known. Remove personal paths and song metadata from logs. Do not upload copyrighted music to reproduce a problem; prefer a generated minimal sample.

Never include signing keys, tokens, personal libraries or build caches. Contributions to original code are provided under this project's MIT license. Respect existing licenses when introducing third-party material.
