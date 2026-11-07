# Android 0.7 validation

Automated verification is separate from device evidence. No Android device was
connected during this implementation, so no phone timings, battery results,
Android Auto certification, audible quality comparisons, or visual sign-off are claimed.

## Automated checks

Run `bash scripts/build-android.sh` from the project root. This builds debug and
optimized preview variants, runs the JVM/Robolectric tests, and lints both variants.
New regression coverage includes duplicate queue entries and shuffle persistence,
empty queue persistence, invalid snapshot rejection, sort ordering and pagination,
10,000-song sorting correctness, MP3/FLAC audio and metadata preservation, and
partial-write rollback / retained originals when rollback fails.

## Phone checks

Install the 0.7.0 preview over the existing app, without uninstalling (same signing
key and package). Confirm favorites, playlists, folders and history remain.

1. Start a song, seek, shuffle and reorder the queue (include duplicates). Pause,
   force-stop and reopen: queue/order/position should return paused. During playing,
   abrupt process loss can lose up to 10 seconds since the periodic checkpoint.
   Empty the queue, restart, and confirm it stays empty. Test disconnected storage.
2. Compare 100 / 1,000 / 10,000 songs. Scroll Songs, search, open album/artist/folder,
   sort in both directions, select many songs, and add them to queue/playlist.
   After upgrading, scan once to populate genre and exact folder metadata.
3. Add the Still Music widget from the launcher. Test Play/Pause, Previous, Next,
   open app, restart the service, remove/re-add widget, dark/light launcher and
   enlarged text. Removing all widgets must not schedule periodic work.
4. Connect Android Auto (development sideloads may require its unknown-sources
   setting). Browse Songs, Albums, Artists, Favorites, On Repeat, Playlists and
   Folders; test search, start music, steering-wheel controls, unplug/reconnect.
   This supplies a MediaLibraryService, not a Play Store automotive approval.
5. With disposable MP3/FLAC copies, edit selected fields on one song, then many.
   Verify unchecked fields, embedded art/lyrics, ReplayGain comments and audio stay
   unchanged. Cancel after a file, deny folder access, disconnect storage, fill
   storage, and test unsupported formats. Confirm completed/failure counts.
   If a write is interrupted, retain app data and recover the original through
   Settings → Recover interrupted edits, then scan again. This safety control
   appears only when a file-edit transaction needs recovery.
6. Test screen-off playback, interruptions, Bluetooth and USB, unplug-to-pause,
   timer, lyrics, shuffle, On Repeat qualification, and all existing codecs.
7. Test large text, TalkBack, small phones and landscape; controls should retain
   usable targets and selection must not unexpectedly start playback.

## Performance measurements

With one authorized phone connected, run `bash scripts/profile-android.sh`.
It force-stops/relaunches Still five times and collects startup timing, process
memory and frame stats. This interrupts playback; it does not edit music. Report
phone model, OS, app build, song count and storage type alongside results. Compare
optimized builds under the same conditions. Cold process starts still benefit from
OS file caches. Collect frame stats after actual scrolling; do not infer smoothness
from the initial startup frames.

For battery, play the same local album for at least 30 minutes with screen off,
same output/volume, network state and OS battery settings. Compare battery usage
and wake behavior on-device; do not extrapolate APK size or host test speed.

## Sound-quality limits

The decoding/output path is unchanged. FLAC/ALAC support and source bit depth are
not claims of exclusive, bit-perfect, or native-rate DAC output. Android mixing,
output hardware, Bluetooth codecs, gain settings and resampling affect output.
Compare volume-matched playback with DSP disabled on both players before judging
sound. Poweramp/AIMP offer more audio controls; this is distinct from measured
fidelity. ReplayGain was considered but is not enabled by this change: adding a
volume-only approximation would not correctly support positive gain and peak
limiting. Proper DSP needs its own audio-path tests and device verification.

## 0.8 interface redesign

The redesign changes Compose presentation and navigation only. Snapshot comparison against `.build/android-before-redesign.tar.gz` confirms that playback, codecs, scanning, persistence, lyrics lookup, artwork caching, and tag/file writing implementations are unchanged. No data migration is required.

Manual acceptance still required on an Android device:

- Switch Library/Search/Playlists, open collections, open and close the player/settings, and verify retained browsing state and Android Back behavior.
- Check album grids, long titles, empty search, clear search, and keyboard dismissal.
- Long-press songs, select several, and verify queue/playlist/tag operations still target the selection.
- Exercise seek, shuffle, lyrics, favorite, sleep timer, queue jumping/removal/reordering, and return to the mini-player.
- Inspect light/dark appearance, large fonts, short screens, and landscape.
- Confirm file deletion still requires explicit confirmation and folder access where needed.

Device inspection was not performed during this redesign because ADB access was not approved. Build/lint/host tests cannot establish visual correctness, touch behavior, or audio quality on a phone.
