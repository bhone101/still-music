# Development and release preparation

See the [source guide](SourceMap.md) for file responsibilities and the shared Swift formatting command.

## Layout

| Path | Responsibility |
| --- | --- |
| `Sources/Still` | SwiftUI screens, AppKit integration and application state |
| `Sources/StillCore` | Audio engine, queue, metadata, lyrics, library persistence and file writers |
| `Sources/StillTagBridge` | Narrow C++ bridge to TagLib for embedded lyrics editing |
| `Tests/StillCoreTests` | Standalone checks using generated temporary files and mock services |
| `Resources` | Bundle metadata and icon preview |
| `Vendor` | Pinned dependency source and original licenses |
| `scripts` | Build, check, icon-generation and source-package helpers |

## Local verification

```sh
bash scripts/check.sh
bash scripts/build-app.sh
```

The checks use macOS `afconvert` to create synthetic audio. They render audio offline and do not make live lyric requests. `swift run StillChecks` alone requires TagLib to have been built already.

For isolated manual app testing:

```sh
STILL_LIBRARY_PATH="$PWD/.build/manual-library.json" "build/Still Music.app/Contents/MacOS/StillMusic"
```

This isolates the library files, not all UserDefaults preferences. Avoid changing personal preferences during a test session.

The optional `swift run StillChecks --verify-output-rates` changes the shared output device's sample rate and attempts to restore it. Run it only deliberately, after pausing other audio. It is never part of CI. See [audio verification](AudioVerification.md).

## Build behavior

Builds target the host architecture, with macOS 14 as the deployment target. Generated icons and compiled products stay under `.build/` or `build/`; a build must not rewrite source assets. The app bundles TagLib statically and includes its license notices. Ordinary builds use ad-hoc signing, not a Developer ID identity.

GitHub Actions builds and runs checks on Apple silicon and Intel macOS runners. These jobs cannot verify audible playback, external DAC behavior, notarization, or UI fidelity; their first hosted run still needs review after the repository is created.

## Preparing the first GitHub upload

1. Review `git status --short` and the source inventory from `bash scripts/package-source.sh`.
2. Keep generated files, credentials and deferred platform work excluded. Review the actual staged diff before committing; never force-add ignored directories.
3. Create the repository and push only after reviewing the contents. Enable private vulnerability reporting under repository Settings → Security.
4. Wait for both CI jobs to pass. Record any known platform limitations in the release notes.

The source packager requires Python 3.9 or later and uses Git's tracked/non-ignored file inventory. It deliberately omits Android source and build tools because this archive is macOS-only, and rejects build caches, common credential filenames and unexpected top-level files even if accidentally force-added. It creates a source archive and a file manifest under `build/`. This filename check is not a substitute for reviewing file contents for secrets.

## Before distributing binaries

Run `bash scripts/build-dmg.sh` to build an app and a compressed disk image for the host architecture. It includes an Applications shortcut and installation instructions, verifies the app signature and disk image, and writes a SHA-256 checksum beside the DMG. CI runs this on Apple silicon and Intel and retains the packages as workflow artifacts for 14 days.

To publish a version, wait for both jobs on the intended commit to pass, download their DMG/checksum artifacts, verify the checksums, and attach both architectures to a GitHub Release targeting that exact commit. Include the corresponding source archive and license notices. Mark preview releases as prereleases. Update the README download links when changing versions; publishing source changes alone does not replace the release assets. If a release is defective, remove its download links and withdraw the affected assets until a fixed version passes verification.

- Retest local playback, queues, sleep/wake, output-device changes and lyrics following.
- Exercise lyric/cover write and delete paths on disposable copies, including failures; compare audio payloads and other tags.
- Check keyboard navigation, VoiceOver, theme contrast and narrow layouts.
- Confirm source, license texts and version metadata accompany the release.
- Decide whether to provide architecture-specific builds or a separately validated universal build.
- Configure Developer ID signing/notarization separately if offering trusted public downloads. Never commit private keys or signing credentials.

## Signed and notarized releases

`bash scripts/notarize-release.sh` runs checks, builds with hardened runtime and secure timestamps, signs the bundled decoder and app, submits the app to Apple, verifies Accepted status, staples and validates the ticket, assesses Gatekeeper, then creates, signs, notarizes and staples the DMG. Its final checksum is generated after stapling. It does not publish or upload a GitHub release.

Set `STILL_SIGN_IDENTITY` to an installed **Developer ID Application** identity (or its SHA-1) and `STILL_NOTARY_PROFILE` to credentials previously stored with `xcrun notarytool store-credentials`. Keep credentials in Keychain; do not put secrets in source or shell scripts. A valid Apple Developer account/certificate is required. Ordinary builds remain ad-hoc signed when the identity is unset. No valid signing identities were available during the 0.2.0 implementation, so Apple notarization has not been performed.

The decoder is compiled offline from the pinned FFmpeg source archive, with only the local Ogg/APE/WavPack demuxers, Opus/Vorbis/APE/WavPack decoders and float PCM pipe output (CAF is enabled for reference tests). Inspect `.build/decoder/configure.log` and `build.log` for diagnostics. The app ships the complete source archive, build instructions and LGPL license alongside the executable.

## Performance safeguards

Library persistence uses a serial utility writer and a separate position checkpoint. Browsing results are cached until their inputs change; only progress and synced lyrics observe the playback clock. Batch tag edits publish one library update, and artwork mappings reuse unchanged album keys.

Extra codecs stream through a bounded pipe with four scheduled 16,384-frame buffers and one pending read. One successor may hold a prefetched buffer. Decoder cancellation terminates the child process, with a forced-stop fallback; a 15-second read timeout handles stalls. Tests compare decoded and engine-rendered samples to reference CAF output, check seeks/cancellation, and verify that position checkpoints do not rewrite the library.
