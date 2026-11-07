#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
tools_dir="$project_root/.android-tools"
export ANDROID_HOME="$tools_dir/sdk"
for jdk_dir in "$tools_dir"/jdk-*/Contents/Home; do
    if [[ -x "$jdk_dir/bin/java" ]]; then export JAVA_HOME="$jdk_dir"; break; fi
done
export GRADLE_USER_HOME="$tools_dir/gradle-home"
export ANDROID_USER_HOME="$tools_dir/android-user"
cd "$project_root/android"
"$tools_dir/gradle-8.11.1/bin/gradle" --offline :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assemblePreview :app:lintPreview "$@"
mkdir -p "$project_root/build/android"
cp app/build/outputs/apk/debug/app-debug.apk "$project_root/build/android/Still-Music-0.8.0-debug.apk"
cp app/build/outputs/apk/preview/app-preview.apk "$project_root/build/android/Still-Music-0.8.0-preview.apk"
printf 'APK: %s\n' "$project_root/build/android/Still-Music-0.8.0-preview.apk"
