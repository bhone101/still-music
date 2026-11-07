# Changelog

## 0.2.0 — unreleased

- Add per-song permanent audio-file deletion with a warning showing the full path; retain the library entry if deletion fails.

- Add local On Repeat beneath Favorites: rolling 30-day listening history, automatic ranking, and qualified-play tracking that excludes skips and seeks.

- Use native macOS inset-list selection and semantic text colors, quieter sidebar icons, tighter library spacing, and evenly spaced transport controls.
- Use compact song rows by default and add visible song action menus.
- Remove the redundant song-list edit footer; keep editing in song menus and the File menu.

- Native song selection with Command/Shift selection and double-click playback.
- Edit selected songs directly, with batch progress, between-file cancellation and result summaries.
- Adapt the library, player and tag editor to compact windows down to 640 × 480.

- Move library saves off the main thread; checkpoint playback position separately.
- Cache library views and isolate playback-clock UI updates.
- Apply batch tag updates and artwork-map refreshes once per batch.
- Stream extra codecs through bounded memory buffers with cancellation, read timeout and next-song prefetch.

- Persistent playback queue, order, shuffle and loop state.
- Reviewed single/batch tag edits and broader cover writing for FLAC/MP3/M4A.
- Explicit MusicBrainz/Cover Art Archive cover search.
- Bundled offline decoding for Opus, Ogg Vorbis, APE and WavPack.
- Developer ID hardened-runtime signing and notarization workflow (credentials required).

## 0.1.1 — 2026-10-18

- Add a Play button to Favorites, matching other playlists.
- Keep lyrics actions in a compact menu at the top left of the lyrics panel.
- Center lyrics within their panel and smooth synced-line transitions.
- Respect Reduce Motion when following synced lyrics.

## 0.1.0 — macOS open-source preview

- Native local playback, library browsing, favorites, saved playlists and queue controls.
- Plain/synced local lyrics, optional online lookup and explicit embedded lyrics editing.
- Local artwork selection and optional FLAC cover writing.
- Source-format information and automatic output sample-rate matching.
- Lyrics action buttons retain text and wrap at narrow widths.
- MIT license for original code, dependency notices, contributor documentation and macOS CI.

These releases are early previews. The downloadable apps are ad-hoc signed and are not Developer ID signed or notarized.
