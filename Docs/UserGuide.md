# Still Music user guide

[Back to the project overview](../README.md)

A small, native macOS music player. SwiftUI interface, AVFoundation playback, local playback by default, and bundled TagLib for embedded lyrics editing.

## Run

Running the app requires macOS 14 or later. Building requires Apple's Swift/C++ command line tools (or Xcode) and CMake (`brew install cmake`). The build script compiles the pinned TagLib source included in `Vendor/`; the finished app requires no separate TagLib installation.

```sh
bash scripts/build-app.sh
open "build/Still Music.app"
```

The build script creates a locally signed app in `build/Still Music.app`. You can drag it into Applications. This build targets the architecture of the Mac that builds it; distribution and notarization are not configured.

## Included

- Add files or folders, or drop them into the window. Folder imports include subfolders.
- Still Music remembers imported folders and scans for new songs at launch and about every five minutes while running (also on returning to the app if a scan is due). Existing libraries start with the parent folders of their songs. Empty imported folders are remembered. Scans run in the background and skip existing songs and unavailable drives. They reconcile missing paths with a unique existing match using tags and source audio properties, so moving songs and moving them back does not leave stale library entries. Existing copies, ambiguous matches, and offline-volume entries are retained. Favorites and queue references follow repaired paths without restarting playback. The first repair saves a `library.before-path-repair.json` backup. Removed library entries stay excluded from automatic scans; manually importing them again restores them. Folder paths and exclusions are saved alongside the library in `library.folders.json`, without changing `library.json`.
- FLAC, ALAC, WAV, AIFF, MP3, AAC, and CAF through the native macOS decoders.
- Original source sample rate and bit depth displayed when available.
- Bit Rate column shows average encoded audio bitrate in kbps, excluding metadata and artwork. Existing libraries refresh this value automatically.
- Play/pause, next/previous, seeking, and automatic advance through the library.
- Track metadata and embedded album art, with a simple fallback for untagged files.
- Bottom now-playing bar with artwork, title, artist, album, source quality, and elapsed/remaining time.
- The player sits beneath the content pane, leaving the sidebar full height. Song information and progress use half the bar; playback controls use the other half. The playback-mode button cycles Shuffle → Loop → Off. Shuffle reorders upcoming songs; Loop repeats the entire queue. The Queue popup lists upcoming entries and lets you jump to one, drag rows to reorder them, or remove individual entries with the minus button. Clear All removes upcoming entries and turns off loop so playback ends after the current song; the current track and library stay intact. Manual ordering becomes the baseline when shuffle is turned off. Right-click a song for **Play Next** or **Add to Queue**; duplicate entries are allowed. The queue and shuffle state last for the current app session.
- Click anywhere on the compact player except its buttons and seek slider to expand Now Playing inside the content pane. The expanded player resizes with the sidebar, shows artwork and controls beside local lyrics, and collapses with the down arrow or Escape. Lyrics are shown only in this expanded view. With no app draft or explicit written/deleted state, lookup follows same-name `.lrc`, then `.txt`, then embedded FLAC LYRICS/UNSYNCEDLYRICS, MP3 USLT/SYLT, or M4A lyrics. UTF-8, BOM-marked UTF-16, Windows-1252, and Latin-1 text are supported. Optional online lyrics are tried only after local sources; lyrics are never stored in the library JSON.
- Timestamped lyrics highlight and follow playback; click a line to seek. Manual scrolling pauses following until **Resume following** or a lyric click. LRC offsets are milliseconds: positive offsets show lyrics earlier. Plain lyrics remain scrollable text; unavailable lyrics show “No lyrics found”.
- Embedded cover thumbnails in songs and albums. FLAC PICTURE blocks prefer the front cover; native cover metadata supports formats such as MP3 and M4A. Album views use the first available embedded image in the album. Files without artwork show a placeholder.
- Artwork loads asynchronously and is downsampled into a bounded memory cache. Refresh Song Metadata also refreshes cover art. Covers are added from local images only.
- Artists show circular artwork using an embedded cover from their songs, with a person placeholder when none is available. Sidebar icons share the blue used by the play button.
- Sidebar views for Songs, Albums, Artists, Genres, Composers, Folders, and Favorites.
- Album grouping uses album artist; Artists also groups by album artist, falling back to the performing artist. Album tracks sort by disc and track numbers when available.
- Read title, performing artist, album, album artist, genre, and composer from native metadata and FLAC Vorbis comments. Missing tags appear as Unknown; no online metadata guessing.
- Existing libraries refresh their metadata in the background. Use **File → Refresh Song Metadata** after editing tags externally.
- Search by title, artist, album artist, album, genre, or composer. Click a category to browse its songs; playback follows the selected list.
- Heart buttons add songs to Favorites. Choose Light or Dark under **Settings → Theme** in the sidebar; favorites and appearance persist on relaunch.
- Library, selected track, and position restored on relaunch (paused).
- macOS Now Playing and media commands.
- Right-click a track to show its file in Finder or remove it from the library. Removal never deletes the audio file.
- Right-click any song and choose **Details** for a read-only sheet of tags, source audio properties, and file information. Missing values are hidden. Opening Details does not start playback, edit files, or change the saved library format.

Keyboard: **⌘O** adds music, **Space** plays/pauses, **⌘→ / ⌘←** skips tracks.

The sort button beside the library count offers **Sort By** and **Order** submenus. Songs support title, artist, album, date added, and quality; album contents also offer track number. Albums sort by title or song count. Artists, genres, and composers sort by name or song count; folders also support full path. Choices are remembered separately for each section and its song lists. Date Added follows saved import order. Quality compares lossless source depth, sample rate, then bitrate (descending places higher quality first).

## Audio scope

High-resolution files are decoded locally by AVAudioFile and played through AVAudioEngine. Output sample-rate matching is always enabled in normal use, with no Settings control, output-format UI, or rate-related messages. A hidden `StillDebugMatchOutputSampleRate` UserDefaults key defaults to true for debugging; the former Settings preference is ignored. Still Music queries the default output’s available rates and selects the source rate or smallest supported integer multiple. If the target already equals the current rate, no hardware write occurs. Unsupported/refused changes fall back silently to the current device format.

Before switching, Still Music fades its own mixer down over approximately 8 ms and stops rendering. It waits for CoreAudio rate confirmation, starts the graph muted, and fades back to unity. This never changes the shared device volume. Transitions are serialized across rapid song changes. Same-rate transitions skip rate writes. Mid-song engine configuration recovery uses the device’s current rate instead of reasserting the file rate, avoiding repeated rate changes during recovery; a new song or output-device change enables matching again. Hardware-specific pops or delays cannot be ruled out without testing the output device.

The original rate is restored at end-of-queue, explicit Stop, removal of the playing track, normal quit, or switching away from an output device. A temporary pause retains the rate. A default-device listener remains active while paused; output changes restore the former device and reconnect playback silently when it was running. Restoration failures are silent and retained for retry. Forced termination or an unplugged device can prevent restoration. Compatible consecutive tracks alternate between two player nodes on the same engine clock for gapless automatic transitions. Queue edits replace only the standby node, leaving the current song and mixer gain untouched. Their decoded sample rate and channel format must match. Rate/channel changes use the quiet reconfiguration path; manual skipping or seeking may interrupt playback. Still Music does not claim end-to-end bit-perfect DAC output.

The graph is two alternating players → mixer → output, with no effects or extra sample-rate conversion node. The file is decoded as 32-bit float at its source rate; when hardware rates match, the mixer/output use that rate too. Float32 can represent up to 24-bit PCM exactly; 32-bit integer sources are not claimed to be bit-exact. No EQ, normalization, ReplayGain, or dithering is applied by Still Music. Playback uses unity app volume; loudness is controlled by macOS. Legacy saved app-volume values are ignored because the in-app volume control was removed. The existing volume field is retained in library JSON and saved as 1 for compatibility. System volume, mixing, channel mapping, and device processing may still alter the output. The quality label describes the **source file**, not a verified DAC signal.

To check on hardware: note the output rate in Audio MIDI Setup, then play 44.1/48/96 kHz files. Try consecutive same-rate songs, unsupported rates, rapid next/previous, pause/resume, switching output devices, reaching the end of the queue, and quitting. Confirm no rate-related UI appears and that the former device’s rate is restored. Automated checks cover simulated rate selection/restoration failures, device changes, offline fades, and exact 16/24-bit PCM output across track boundaries at 44.1/48/96/192 kHz. Normal checks do not change device rates. Run `swift run StillChecks --verify-output-rates` for an explicit physical rate-switch/restore check; pause other playback first. This confirms nominal hardware rates, not captured DAC samples.

Ogg/Vorbis/Opus, APE, WMA, and DSD are not part of the initial supported format list. Decoder support for optional codecs differs across macOS versions. DRM-protected streaming-service downloads are unsupported.

## Lyrics management and optional covers

The expanded player always shows **Find online**, **Import lyrics**, **Write lyrics to file**, and a single **Discard changes / Delete lyrics** button. It shows Discard changes for an app draft and switches to Delete lyrics after writing or discarding. Unavailable actions are disabled. On narrow windows the buttons wrap onto additional rows while keeping their icons and text visible.

**Import lyrics** imports a nonempty local `.lrc` or `.txt` up to 8 MiB into app storage. It never uploads anything to a server and never changes the audio or sidecar files. **Find online** explicitly searches LRCLIB for one song, including when automatic search is off, and stages the result in the app. Explicit searches can replace the displayed uploaded/synced lyrics when a match is found. No match or a network failure keeps the existing lyrics. Both uploaded and online drafts persist in `library.lyrics`, take priority during normal playback, and are keyed by the song's standardized file path. Moving a song currently does not migrate these associations.

An **Unsaved changes** indicator appears whenever the displayed lyrics are an app draft, including after relaunch. **Discard changes** removes that draft without editing the audio or sidecars. It returns to the previously committed source: embedded lyrics after a write, empty after a deletion, or local sidecar/embedded lyrics otherwise. Automatic search stays suppressed after discard so it cannot immediately recreate the draft; Find online and Import lyrics remain available. Replacing a draft repeatedly does not change this baseline.

**Write lyrics to file** replaces the song's embedded lyrics after confirmation. It supports both plain and synced lyrics in FLAC, MP3, and M4A/MP4 (including ALAC in M4A). FLAC uses `LYRICS` Vorbis comments, MP3 uses ID3 USLT, and M4A uses `©lyr`. Synced lyrics are serialized as LRC timestamps inside the text tag; Still recognizes these timestamps, while other players' support can vary. Existing FLAC `LYRICS`/`UNSYNCEDLYRICS` and MP3 USLT/SYLT lyrics are removed before replacement. After success the draft is removed, the embedded version takes priority over separate sidecars, and a three-second **Lyrics written to file** confirmation appears. There is no automatic lyrics-writing setting; the former `StillAutoSaveLyrics` preference is ignored. Uploads and searches alone never write to audio files.

**Delete lyrics** asks for confirmation, removes embedded lyrics from the supported audio file, removes the app draft, and clears the display. It does not restore earlier lyrics. A persistent cleared state prevents sidecars or automatic online lookup from immediately repopulating the display. Import lyrics or Find online can stage new lyrics afterward. Separate `.lrc`/`.txt` files remain untouched on disk. Old restoration snapshots are no longer used; they are cleaned up when a new draft, write, or delete is recorded.

TagLib edits only an adjacent temporary copy, then Still replaces the original atomically after a successful save and a check that the original has not changed. There is no decoding or re-encoding. Read-only/invalid files and write failures produce an error without replacing the original. Other formats remain readable but have embedded write/delete disabled. TagLib 2.2.1 is statically bundled under its MPL license option; complete dependency source and notices are in `Vendor/`, and license notices are included in the app.

Without an app draft or an explicit written/cleared state, local lookup uses same-name `.lrc`, then `.txt`, then embedded FLAC/ID3/M4A lyrics. Timestamped lines highlight and follow playback; clicking a line seeks. Manual scrolling pauses following until **Resume following** or a lyric click. Plain text remains scrollable. Lyrics are never stored in `library.json`, and no embedded lyrics editor or timing editor is included.

Settings has two independent switches, both **off by default**:

- **Find lyrics online:** when local lyrics are missing or unsynced, search [LRCLIB](https://lrclib.net/docs) with the song title and artist. Returned records must match title/artist and be within two seconds of the source duration; album matches are preferred locally. Synced results can replace plain local lyrics in the player; otherwise local lyrics remain. Automatic search does not replace app drafts, explicitly written lyrics, or a cleared state. Accepted results are staged in the app only. The network cache (including misses) is in memory, with up to 256 entries.
- **Write covers into files:** explicitly chosen covers are also written into that album’s FLAC files, one at a time. MP3/M4A and other formats retain the selected cover in the app only. JPEG/PNG selections preserve their resolution (up to 8192 pixels per dimension and under 16 MB). The cover writer replaces front-cover PICTURE blocks in a temporary file, copying audio and other metadata unchanged. Turning this off does not undo previous writes. This cover preference is independent of lyrics actions.

Right-click a song or album for **Choose Album Cover…**. There is no online cover lookup. App covers are stored in `library.covers` and take priority over embedded art.

LRCLIB receives the search title/artist and normal connection information such as IP address, never audio files, uploaded lyric files, or local paths. Automatic requests are off by default; pressing Find online explicitly requests a search. Requests use HTTPS, timeouts, response-size limits, and at least 1.1 seconds between requests. Ordinary checks use mock services and never send library metadata online.

Manual checks: on copies of a FLAC, MP3, and M4A, upload synced then plain lyrics and verify the audio files stay unchanged. Choose Write lyrics to file; cancel once, then confirm. Reopen the files and verify embedded lyrics, other tags, artwork, and playback. Delete; cancel once, then confirm, and check that lyrics remain empty after a restart. Verify separate sidecars remain on disk and that a new upload/search can stage lyrics again. Try a read-only file and an unsupported format. For covers, verify the separate preference still writes only FLAC covers.

## Audio diagnostics

Audio diagnostics are internal troubleshooting information and are hidden from Settings, including the export button. They are not required for listening and do not improve sound quality. Nothing is uploaded. Still Music retains the latest 256 events in `library.audio-diagnostics.json` alongside the library; automatic writes run on a background serial queue. The log contains timestamps, fixed event names, numeric device IDs, sample rates, and numeric error codes. It never collects song titles, tags, file paths, device names, or free-form error descriptions. Playback events, engine configuration changes, device changes, rate requests/confirmations/failures, and restorations are recorded. Corrupt logs are ignored and diagnostics failures do not interrupt playback. The library JSON format is unchanged.

To check queue edits: play a long song and repeatedly choose **Play Next**, **Add to Queue**, or cycle shuffle/loop. The current song should continue without jumping or fading, and the latest queue order should take effect at the boundary. Also try removing an upcoming song, including one with a different sample rate. A boundary that has already started rendering counts as the new current song; queue edits cannot recall audio already sent to the device.

## Playlists (Mac)

Click **+** beside **Playlists** in the sidebar. Enter a name to create it; saved playlists appear below Favorites. Open a playlist and choose **Add songs** to select library songs, or right-click any song and use **Add to playlist**. Duplicate additions are prevented. Play starts that playlist’s visible song order. Right-click playlist songs to move them up/down or remove them from the playlist; neither operation changes the source files. Search filters the displayed songs without changing the saved order.

Right-click a playlist (or use its header menu) to rename or delete it. Deletion requires confirmation and leaves the music library and current playback queue intact. Playlist edits are saved atomically in `library.playlists.json` beside the existing library, preserving `library.json`’s format. Folder-path repairs update playlist references, and removing a song from the library removes its playlist memberships.

Manual checks: create a playlist using **+** beside **Playlists**, add several songs using both the picker and song menu, try adding the same song twice, reorder and play it, rename it, then relaunch to check persistence. Remove a playlist song and verify it remains in Songs. Delete the playlist and verify playback and source files remain intact.

## Storage

Audio files stay in their original locations. The library stores references and metadata in `~/Library/Application Support/Still/library.json`. The original storage path and bundle identifier (`com.still.musicplayer`) are retained so existing Still libraries and preferences carry over to Still Music. Disconnected files remain unavailable until their volume returns. Scans repair moved paths when there is a unique metadata match; ambiguous moves may need manual re-import. There is no account, telemetry, upload, folder watcher, or automatic copying.

For isolated development sessions, set `STILL_LIBRARY_PATH` to a different JSON file before launching the executable.

## Typography

The app uses the native macOS system font through SwiftUI's `.system` API, including the system monospaced design for audio readouts. No font files are downloaded, bundled, or redistributed. This follows Apple's system-font integration for native Apple-platform apps: [Apple fonts documentation](https://developer.apple.com/documentation/technologyoverviews/fonts). Future non-Apple versions will need their own platform fonts or a suitably licensed bundled font.

## Tests

```sh
bash scripts/build-taglib.sh
swift run StillChecks
```

The standalone checks run with Command Line Tools and the built TagLib dependency, without XCTest or a full Xcode installation. Embedded lyrics checks compare encoded audio payloads byte-for-byte before and after writes/deletions in FLAC, MP3 and M4A, verify tag/artwork preservation, draft persistence, and failure handling. They generate synthetic PCM audio and convert it with Apple's `afconvert`, checking high-resolution decoding, source metadata, folder import, duplicate handling, missing/corrupt files, and library persistence.
