# Audio verification

This document separates historical hardware observations from offline automated checks. Hardware results below were recorded on 2026-10-05 and are not a certification of other devices or later builds.

## Source-release checks — 2026-10-15

`bash scripts/check.sh` passed all 25 checks on Apple silicon. These cover audio rendering, artwork, metadata, grouping, sorting, lyrics, queue behavior and library persistence. The normal check command uses generated fixtures and mock network services; no hardware-rate check was run for this preparation.

## Historical results — 2026-10-05

`swift run StillChecks` passed all 15 checks. `bash scripts/build-app.sh` built and signed Still (now Still Music) successfully.

The offline engine tests compared every stereo sample from two consecutive files against the original decoded PCM, including the track boundary. That implementation used one running AVAudioEngine/AVAudioPlayerNode. The current two-node scheduler is covered separately below. No fades are applied at the automatic boundary.

| Sample rate | 16-bit WAV pair | 24-bit FLAC pair | Frames compared per pair |
| --- | --- | --- | --- |
| 44.1 kHz | Exact match | Exact match | 22,050 |
| 48 kHz | Exact match | Exact match | 24,000 |
| 96 kHz | Exact match | Exact match | 48,000 |
| 192 kHz | Exact match | Exact match | 96,000 |

The checks also cover successor completion notifications and rejection of incompatible sample rates. Existing checks cover queue duplicates, shuffle, loop, seeking, fades, source metadata, and simulated rate-selection/restoration failures.

## Physical output rate check

The selected device was Conexant USB Audio (Synaptics), stereo output. After pausing the user's playback, `swift run StillChecks --verify-output-rates` confirmed these nominal rates through CoreAudio:

- 44,100 Hz → 44,100 Hz
- 48,000 Hz → 48,000 Hz
- 96,000 Hz → 96,000 Hz
- 192,000 Hz → 192,000 Hz

The original pre-test rate of 48,000 Hz was restored, then user playback resumed. No test audio was played by the hardware-rate check.

## Scope and limits

These results verify software-rendered PCM and the physical device's nominal rate, not the DAC's actual received sample values. No digital loopback/capture route was available. System mixing, hardware volume, DSP, channel mapping, or device firmware can alter the signal after the engine. End-to-end bit-perfect output is not claimed.

Gapless automatic transitions require a successfully preloaded successor with the same decoded processing format (sample rate/channel format). A rate/channel change reconfigures the engine quietly. Manual skips, seeks, device changes, unusually short tracks, or decode failures can interrupt playback. Encoder padding already present in a file is not removed by this scheduling change.

To repeat the physical test, pause playback first. The optional command changes the shared output rate temporarily and restores it; ordinary StillChecks runs render offline and leave the device rate unchanged.

## Queue replacement and diagnostics checks

The two-node scheduler is checked against decoded source samples while replacing/clearing the upcoming song three times during the current track, including 128 frames before its end. Checks include a seeked starting position, repeated node reuse across three songs, no successor, and 44.1/96/192 kHz 24-bit PCM. The current playback clock must remain unchanged by edits; every rendered sample must match the expected concatenation. Normal 16/24-bit boundary tests continue to cover 44.1/48/96/192 kHz.

Diagnostics checks cover bounded retention, ordered atomic persistence, loading corrupt logs, safe export without file/error-description strings, and rate request/confirmation/failure/restoration events. These automated checks do not confirm audible behavior on physical USB hardware.
