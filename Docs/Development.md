# Development and release preparation

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

The source packager requires Python 3.9 or later and works before the first commit, using Git's tracked/non-ignored file inventory. It rejects Android paths, build caches, common credential filenames and unexpected top-level files even if accidentally force-added. It creates a macOS-only source archive and a file manifest under `build/`. This filename check is not a substitute for reviewing file contents for secrets.

## Before distributing binaries

Run `bash scripts/build-dmg.sh` to build an app and a compressed disk image for the host architecture. It includes an Applications shortcut and installation instructions, verifies the app signature and disk image, and writes a SHA-256 checksum beside the DMG. CI runs this on Apple silicon and Intel and retains the packages as workflow artifacts for 14 days.

To publish a version, wait for both jobs on the intended commit to pass, download their DMG/checksum artifacts, verify the checksums, and attach both architectures to a GitHub Release targeting that exact commit. Include the corresponding source archive and license notices. Mark preview releases as prereleases. Update the README download links when changing versions; publishing source changes alone does not replace the release assets. If a release is defective, remove its download links and withdraw the affected assets until a fixed version passes verification.

- Retest local playback, queues, sleep/wake, output-device changes and lyrics following.
- Exercise lyric/cover write and delete paths on disposable copies, including failures; compare audio payloads and other tags.
- Check keyboard navigation, VoiceOver, theme contrast and narrow layouts.
- Confirm source, license texts and version metadata accompany the release.
- Decide whether to provide architecture-specific builds or a separately validated universal build.
- Configure Developer ID signing/notarization separately if offering trusted public downloads. Never commit private keys or signing credentials.
