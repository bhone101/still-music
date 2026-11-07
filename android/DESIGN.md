# Still Android interface

The interface adapts the supplied “Still for Android — Spotify layout” reference in both light and dark appearances. Home, Search and Library are the primary destinations. Each retains its browsing state when opening the player, queue or settings. Back exits selection, then a collection, then a category, and finally returns to Home.

## Browsing

Home has a time-aware greeting, scan/settings actions, two-column shortcuts, a Recently played artwork shelf and an Albums shelf. Content comes from the user's library. Recently played uses the existing qualified listening history; an empty history shows an explanation instead of sample music.

Search has a dedicated field and Browse all cards for Songs, Albums, Artists, Genres and Folders. Composer browsing is omitted because the current Android catalog does not store composers. Library combines Favorites, On Repeat, saved playlists and albums, with Playlists/Albums/Artists filters and a create-playlist action. Add music and Scan library remain available.

## Appearance and playback

Black and white backgrounds, compact rounded surfaces, bold headings and blue accents follow the reference. Text truncates or wraps; interactive controls retain 48 dp targets. The mini-player includes artwork, song/artist, favorite, play/pause and progress. The full player keeps large artwork, quality information, seek/time, shuffle/previous/play/next/timer, and separate lyrics and queue controls. Portrait scrolls and landscape retains side-by-side panels. The queue uses artwork rows with Now playing/Up next labels and retains removal, drag reordering and accessible move actions.

The existing selection, playlist, tag editing, file deletion confirmations, lyrics and sleep timer workflows remain in place. No decoder, scanning, storage or playback-service logic changes are required by this layout.

## Validation

Run `bash scripts/build-android.sh` for debug/optimized APKs, JVM regression tests and lint. Device checks should cover both themes, large text, rotation, Back navigation, long titles, empty libraries, playback controls and queue reordering. Automated checks do not replace rendered-device or listening tests.
