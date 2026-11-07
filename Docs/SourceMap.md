# Source guide

## App and interface — `Sources/Still`

| File | Responsibility |
| --- | --- |
| `StillApp.swift` | App entry point, window, menu commands, and app lifecycle |
| `PlayerModel.swift` | Observable app state; coordinates playback, import, metadata, playlists, and persistence. MARK sections identify the main workflows. |
| `ContentView.swift` | Sidebar, library, settings, song actions, and Now Playing layout |
| `Palette.swift` | Adaptive interface colors |
| `ArtworkViews.swift` | Artwork thumbnail and record placeholder views |
| `PlaybackProgress.swift` | Progress slider and playback-clock observation |
| `SongClickObserver.swift` | Native mouse observation for song selection and context menus |
| `WindowBackground.swift` | AppKit window background and title-bar appearance |
| `LyricsView.swift` | Lyrics display, editing controls, and playback following |
| `QueueView.swift` | Queue presentation and editing |
| `PlaylistSheets.swift` | Playlist naming and song selection |
| `MetadataEditor.swift` | Batch tag editor and progress display |
| `ArtworkSearchSheet.swift` | Online album-cover selection |
| `TrackDetailsSheet.swift` | Single-song technical details |
| `ArtworkStore.swift` | Artwork loading, caching, and stored cover overrides |

## Reusable logic — `Sources/StillCore`

- **Library:** `Track`, `LibrarySection`, `LibrarySort`, `LibraryReconciliation`, and `WatchedFolders` describe songs, browsing, and scanning. `LibraryPersistence` handles saved library writes.
- **Playlists and listening:** `PlaybackQueue` and `ListeningHistory` handle queue order, shuffle, and On Repeat. Saved playlists remain managed by the app’s library model.
- **Audio:** `EnginePlayback`, `StreamingAudio`, `ExtendedAudio`, `OutputSampleRate`, and `AudioDiagnostics` implement playback, codec streaming, device-rate handling, and diagnostics.
- **Lyrics:** `LRCParser`, `LyricsLoader`, `ImportedLyrics`, and the lyrics writers handle timing, sources, local drafts, and file updates.
- **Metadata and artwork:** `FileMetadata`, `TrackDetails`, `EmbeddedArtwork`, `FLACComments`, `FLACArtworkWriter`, `OnlineMetadata`, and `CoverSearch` handle tags and cover sources.

`Sources/StillTagBridge` provides the C++ TagLib bridge. Keep its C interface compatible with Swift callers.

## Verification and supporting files

- `Tests/StillCoreTests/AudioTests.swift`: executable regression suite, run through `bash scripts/check.sh`.
- `scripts/`: build, verification, packaging, and signing entry points. See [Development](Development.md).
- `Resources/`: app metadata, icons, and bundled resources.
- `Vendor/`: pinned third-party source and licenses; keep upstream formatting intact.
- `.build/` and `build/`: generated caches, test fixtures, verification logs, and app bundles.
- Local Android work and planning files remain separate from the macOS release.

## Formatting

Use the installed Swift formatter with the checked-in configuration:

```sh
xcrun swift-format format --configuration Docs/swift-format.json --in-place --recursive Sources/Still Sources/StillCore Tests/StillCoreTests Package.swift
```

The configuration uses four-space indentation and a 120-column target. Semantic rewrite rules are disabled; the semicolon rule expands multiple statements into separate lines. Do not format vendor sources or generated files.

After changes, run `bash scripts/check.sh` and `bash scripts/build-app.sh`. Audio-device and visual verification have separate requirements documented in [AudioVerification](AudioVerification.md) and [Development](Development.md).
