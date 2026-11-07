# Still Music for Android — 0.8.0 preview

A fresh Kotlin / Jetpack Compose implementation based on the approved Still design.
This is a local development preview, not a Google Play release. Android 9 or later
is supported; the current cached toolchain targets Android 15 (API 35).

## Build

From the repository root:

```sh
bash scripts/build-android.sh
```

This uses the preserved JDK 17, SDK 35, Gradle 8.11.1 and dependency caches under
`.android-tools/`, in offline mode. It builds debug and optimized preview APKs,
runs JVM checks, and runs Android lint for both variants.

Install `build/android/Still-Music-0.8.0-preview.apk` from the project root.
The preview has code/resource shrinking enabled and is not debuggable. It uses
the local development signing key; it is not production signed. Keep that key
private and unchanged for compatible development updates.

The package ID remains `com.stillmusic.player`, version code 15. This rebuild
uses separate `still-v2` preferences and `library-v2.json` app storage. It does
not migrate or erase the archived version's library/settings. Add your music
folder again after installing. Audio files are deleted only through the explicit Delete song confirmation and Android write permission.

## Design and behavior

- Black/white themes with Still blue accents and native system sans-serif text.
- Home, Search and Library navigation adapted from the supplied Spotify-layout reference; artwork shelves, category cards, collection filters, folder import and manual scan.
- Empty-library Add music action; persistent mini-player with Favorites, Play/Pause and progress. Previous and Next remain in the full player.
- Artwork and lyrics share the Now Playing panel. Short screens scroll;
  landscape places the panel beside the controls.
- Icon-only Shuffle on/off; blue indicates enabled. Playback stops at the queue end.
- Song menus include Play next and Add to queue. They preserve the current song
  and playback position, including shuffle order. An empty queue is prepared
  without starting playback automatically.
- Queue supports jumping, removal and long-press handle dragging, including the
  actual shuffle order. Accessible move actions are available for screen readers.
- Sleep timer bottom sheet: 15/30/45/60 minute presets, custom 1–1440 minutes
  with step controls, or End of song. Start confirms the selection; Cancel keeps
  any existing timer. End of song pauses at the media-item boundary, including
  shuffled playback, and then clears itself. The timer runs in
  the playback service and works independently of the player screen.
- Favorites beside the Now Playing title, playlist deletion menus, and searchable
  song pickers inside playlists. Song menus include file details and permanent
  deletion with a warning and a folder write-permission request when needed.
- Larger artwork/lyrics panel, icon-only mode controls, pill search bars and
  outlined appearance cards and consistent Settings surfaces. The library header
  keeps search visible; playlist details have only an Add songs action, with
  search inside the song picker. Small covers are cached on disk and prefetched.
- Background Media3 playback, audio focus, unplug-to-pause and media controls.

## Lyrics and privacy

The app reads same-name `.lrc` then `.txt` sidecars, or embedded FLAC Vorbis lyrics,
MP3 ID3v2.3/v2.4 USLT and M4A lyrics. Metadata reads are bounded. Some uncommon
ID3 encodings/flags, timed SYLT frames and non-seekable document providers are not
supported by this first embedded-reader implementation. Unsynced text still shows.
Lyrics are center-aligned. Synced lines highlight during playback and can be tapped to seek. Manual scrolling
pauses following; Resume following restores it. Flipping to lyrics or loading
lyrics resumes following immediately.

Automatic online lyrics is off by default. When enabled, lookup also runs while
the mini-player is visible. M4A duration and common tags have a bounded container
reader fallback; saved zero-duration M4A entries are repaired on launch, and
measured playback durations are persisted. When enabled, or explicitly requested,
LRCLIB receives the song title and artist over HTTPS. Duration and album matching
happen locally. Any existing lyrics, plain or synced, prevent online lookup. Matched online
lyrics are saved quietly in app storage and reused even with online lookup off.
Plain online lyrics are accepted when synced lyrics are unavailable. Search
tolerates punctuation and remaster suffix differences and unknown duration with
a known artist. Different live/remix titles remain distinct. Duration differences
over five seconds use plain text rather than potentially incorrect timing.
Network/service errors are displayed separately from no-match results; requests
are serialized and throttled, with a cooldown for rate-limit responses. No audio or paths are uploaded. Network
responses are bounded to 1 MB with connection/read timeouts. No accounts or analytics.

Folder import uses read-only Storage Access Framework grants. Confirmed file
deletion and tag editing request write access to the original folder. Failed deletion keeps
the library entry; successful deletion removes queue and playlist references. Failed folder scans
preserve saved entries. Library data and preferences stay in app storage; backup
and device transfer are disabled. Uninstalling removes app data, not source music.

## Typography and licenses

The UI uses Android's native `FontFamily.SansSerif` and system monospace for quality
readouts. No font files are downloaded, bundled or redistributed. Device/system
font preferences may affect appearance. There is no separate font purchase or
bundled-font license required to distribute this app.

Original app code and logo are covered by the project's MIT license. The existing
logo assets and, with explicit approval, the ALAC/AIFF codec support and its tests
were retained. The old UI, library store and playback controls were not reused.
See `ALAC-NOTICE.md` for the bundled BSD decoder; its license and the project's MIT
license are included in `assets/licenses`. AndroidX and Kotlin are Apache 2.0;
JUnit and Robolectric are test-only dependencies.

## Playback scope

Media3/platform codecs handle MP3, AAC/M4A, FLAC, PCM WAV, Vorbis and Opus. The retained
Java decoder supports 16/24-bit mono/stereo ALAC, and the custom extractor supports
integer PCM AIFF/AIFC. Unsupported files report playback errors. DRM, arbitrary
multichannel ALAC and compressed AIFF are not promised playable.

The compatibility path uses integer PCM rather than forced float output. Source
format information is not a claim of bit-perfect DAC output. Hardware decoding,
Bluetooth, USB output and Samsung power management need real-device checks.

## Verification before wider distribution

Automated tests cover common-format extraction, ALAC packet decoding, AIFF parsing,
embedded metadata boundaries, lyric timing, album grouping and shuffle toggling and On Repeat qualification/ranking.
A successful build does not validate pixels, audible playback or background behavior.

On a phone, test:

1. Empty library → import → scan → relaunch, including unavailable storage.
2. Actual FLAC, AAC, ALAC, MP3, WAV, AIFF, Vorbis and Opus playback; start at low volume.
3. Screen-off playback, incoming interruptions, Bluetooth/USB and unplugging.
4. Shuffle on/off, end of queue, replay after completion, reordering and removal.
5. Timer expiry with the app in the background and timer cancellation/replacement.
6. Playlist/favorite persistence, keyboard-open playlist sheet, long titles,
   light/dark themes, rotation, large text, TalkBack and system gesture insets.
7. Local/synced/missing lyrics, cached offline lyrics, manual scrolling and tap-to-seek.
8. Permanent deletion using disposable test audio: warning cancellation, denied
   write permission, successful deletion, unavailable storage and relaunch.

No phone was connected during the initial rebuild. These device checks and an
exact visual comparison to the PDF remain outstanding. Production signing,
API 36 migration and store submission are separate work. Android source is
tracked in this repository. APKs, signing keys, SDKs and local build caches are
not tracked. A Google Play release is separate from this source publication.

The previous Android implementation remains recoverable in
`../build/android-archive-2026-10-15/`; shared downloads/tools were preserved.

## Mac workflow updates (0.6.0)

- On Repeat sits below Favorites in Playlists. It lists up to 30 available songs ranked by qualified listens in the last 30 days, then recency. History is local and starts with this version. The playback service records a listen after 30 seconds of real progress (half the duration for shorter tracks); skips, seeks, and pauses add no time. Background playback is included.
- Compact rows retain 48 dp menu targets. Long-press selects a song; tap other rows to extend the selection. Cancel/Back exits selection mode. Ordinary tapping still plays music.
- Selection actions add all selected songs to a playlist or the queue, preserving displayed order. Play next preserves that order too. Creating a playlist from the song menu includes the full selection.
- Details, favorite toggling, and permanent file deletion remain single-song menu actions. They are hidden for multi-selection. Android's existing confirmed file-deletion workflow remains distinct from the removed Mac library-only deletion.
- Sleep timer, codecs, phone mini-player, SAF folder access, and existing saved libraries/settings are retained. Artwork and lyrics remain keyed to the song, so pausing/resuming does not reload them.

Phone validation is still needed for long-press selection, large text, background listen counting, and the On Repeat list updating after playback. No Mac-only Finder or right-click behavior is added.


## Library and playback improvements (0.8.0)

- Persisted physical queue, duplicate-entry identity, shuffle order, current song
  and position. Reopening restores paused; active playback checkpoints every ten
  seconds, with immediate saves on pause/seek/queue changes. Storage IO is serialized
  off the player thread. Unavailable storage reports normal playback errors.
- Song sorting by title, artist, album, duration or recent modification, with
  reversible order and saved preference. Folder/genre browsing uses scanned metadata;
  scan once after upgrading. Same-name folders on different roots stay separate.
- Edit tags from single-song or selection menus. Checked Title, Artist, Album,
  Album artist and Genre fields apply to the selected MP3/FLAC files; other formats
  are reported as unsupported. ID3v2.3/2.4 without unsupported header flags and FLAC
  comments are supported, with bounded metadata reads. Embedded art, lyrics,
  unrelated tags and encoded audio are preserved. Audio artwork editing is not added.
- Batch editing shows completed counts and failures; cancellation stops between
  files. Editing the current song pauses playback. Original and edited files are
  staged before writing, failed writes attempt rollback, and interrupted writes
  retain originals. Settings offers transaction recovery only when required.
  This is an editing safeguard, not a general library backup/restore feature.
- Home-screen widget with current title/artist, Previous, Play/Pause and Next.
  Tapping the title opens Still. Updates are event-driven, with no periodic polling.
- MediaLibraryService and Android Auto manifest integration expose Songs, Albums,
  Artists, Favorites, On Repeat, Playlists, Folders and search to trusted browsers.
  Playback controls stay in the same service. Car/device verification is pending.
- Playback-only events reuse queue UI data; browsing caches sorting/grouping;
  duplicate pending library saves are skipped; startup no longer waits for cover
  preloading; scans prefetch only the first 40 covers and scrolling loads others.
- Playlist import/export and library backup/restore remain excluded. Codecs, shuffle
  behavior, sleep timer, local history and existing saved data are retained.

See [VALIDATION.md](VALIDATION.md) for test scope, connected-device checks and
performance measurements. DSP/ReplayGain, exclusive output and DAC rate switching
are not added; source quality labels describe the file, not measured output fidelity.

## Interface redesign (0.8)

Library, Search, and Playlists now have persistent bottom navigation. Library includes an adaptive album grid and dedicated collection browsing; the player, queue, song rows, settings, and editing surfaces use a coordinated light/dark design. See [DESIGN.md](DESIGN.md) for interactions and visual conventions. Existing playback and storage features are preserved.
