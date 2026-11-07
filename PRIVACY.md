# Privacy

Still Music plays local files without accounts, analytics or advertising SDKs.

## Local data

The app stores library references, metadata, preferences, favorites, playlists and app-managed lyric drafts/covers locally. Library files live under `~/Library/Application Support/Still/`; preferences use the existing `com.still.musicplayer` bundle identifier. Audio is not copied into the library. The per-song Delete Song action permanently deletes the source audio only after a warning and explicit Delete File confirmation. Removing a song from a playlist or deleting a playlist keeps source audio.

Explicit tag edits, embedded-lyrics write/delete actions and enabled cover-writing actions modify supported source files. Importing lyric drafts or searching online does not itself modify music files.

## Optional network requests

Automatic online lyrics is off by default. Enabling it, or clicking Find online, sends song title and artist to LRCLIB over HTTPS. LRCLIB receives normal connection data, including the IP address. Matching uses duration and album metadata locally. Audio, local paths and imported lyric files are not uploaded. Network results and misses are cached in memory; accepted lyric drafts may be saved locally by the app.

## Diagnostics

A bounded local audio diagnostic log records timestamps, fixed event names, numeric device IDs, rates and numeric errors. It does not record song titles, paths or device names, and is never automatically uploaded. Reports shared manually should still be reviewed for personal information.

Removing the app does not automatically remove its Application Support data or preferences. Back up that data before manually removing it if you want to keep playlists, favorites or lyric drafts.

## Optional cover search

Find Album Cover sends only the text you submit to MusicBrainz. Album previews and selected covers load from Cover Art Archive and its image hosting redirects (including Internet Archive). These services receive ordinary connection details, including your IP address. Opening the sheet alone does not search. No audio files or local paths are uploaded. Search results do not change your library until you select and apply a cover. The existing cover-writing setting controls whether applying also embeds the image in supported audio files.

Additional audio formats are decoded entirely on your Mac using a bundled executable with network support disabled. Decoded audio stays in bounded memory buffers and is not written to temporary files.
