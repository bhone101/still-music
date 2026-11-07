#!/usr/bin/env bash
# Connected-device measurements only. Does not change the music library.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
adb="$project_root/.android-tools/sdk/platform-tools/adb"
package="com.stillmusic.player"
output="$project_root/build/android/profile-$(date +%Y%m%d-%H%M%S)"
if [[ "$("$adb" get-state 2>/dev/null || true)" != "device" ]]; then
    echo "Connect and authorize exactly one Android device first." >&2
    exit 1
fi
mkdir -p "$output"
"$adb" shell getprop ro.product.model > "$output/device.txt"
"$adb" shell getprop ro.build.version.release >> "$output/device.txt"
"$adb" shell dumpsys package "$package" > "$output/package.txt"
# Each run restarts Still's process. OS file caches remain warm; these are not boot-cold tests.
for run in {1..5}; do
    "$adb" shell am force-stop "$package"
    "$adb" shell am start -W -n "$package/.MainActivity" > "$output/start-$run.txt"
done
"$adb" shell dumpsys meminfo "$package" > "$output/memory.txt"
"$adb" shell dumpsys gfxinfo "$package" framestats > "$output/frames.txt"
printf 'Saved measurements: %s\n' "$output"
echo 'For scrolling: scroll the library on-device, then capture dumpsys gfxinfo again. Startup timing alone does not measure scrolling or battery use.'
