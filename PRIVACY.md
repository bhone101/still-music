# Privacy

Still Music plays local files without accounts, analytics or advertising SDKs.

## Local data

The app stores library references, metadata, preferences, favorites, playlists and app-managed lyric drafts/covers locally. Library files live under `~/Library/Application Support/Still/`; preferences use the existing `com.still.musicplayer` bundle identifier. Audio is not copied into the library. File removal from the library does not delete the source audio.

Explicit embedded-lyrics write/delete actions and enabled FLAC cover-writing actions modify supported source files. Importing lyric drafts or searching online does not itself modify music files.

## Optional network requests

Automatic online lyrics is off by default. Enabling it, or clicking Find online, sends song title and artist to LRCLIB over HTTPS. LRCLIB receives normal connection data, including the IP address. Matching uses duration and album metadata locally. Audio, local paths and imported lyric files are not uploaded. Network results and misses are cached in memory; accepted lyric drafts may be saved locally by the app.

## Diagnostics

A bounded local audio diagnostic log records timestamps, fixed event names, numeric device IDs, rates and numeric errors. It does not record song titles, paths or device names, and is never automatically uploaded. Reports shared manually should still be reviewed for personal information.

Removing the app does not automatically remove its Application Support data or preferences. Back up that data before manually removing it if you want to keep playlists, favorites or lyric drafts.
