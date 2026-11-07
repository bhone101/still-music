#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
SOURCE="$ROOT/.build/ffmpeg-source/ffmpeg-8.0.1"
OUTPUT="$ROOT/.build/decoder"
STAMP="$(shasum -a 256 scripts/build-decoder.sh | cut -d " " -f 1)"
if [[ -x "$OUTPUT/ffmpeg" && -f "$OUTPUT/configuration.stamp" && "$(cat "$OUTPUT/configuration.stamp")" == "$STAMP" ]]; then exit 0; fi
mkdir -p "$ROOT/.build/ffmpeg-source" "$OUTPUT"
printf '%s  %s\n' '05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41' 'Vendor/ffmpeg/ffmpeg-8.0.1.tar.xz' | shasum -a 256 -c -
tar -xf Vendor/ffmpeg/ffmpeg-8.0.1.tar.xz -C "$ROOT/.build/ffmpeg-source"
cd "$SOURCE"
./configure --prefix="$OUTPUT" --disable-everything --disable-autodetect --disable-network --disable-doc --disable-debug --disable-ffplay --disable-ffprobe --disable-avdevice --disable-swscale --disable-x86asm --enable-ffmpeg --enable-protocol=file,pipe --enable-demuxer=ogg,ape,wv --enable-decoder=opus,vorbis,ape,wavpack --enable-parser=opus,vorbis --enable-encoder=pcm_f32le --enable-muxer=caf,pcm_f32le --enable-filter=aresample,aformat,anull --extra-cflags=-mmacosx-version-min=14.0 --extra-ldflags=-mmacosx-version-min=14.0 > "$OUTPUT/configure.log" 2>&1
make -j "$(sysctl -n hw.ncpu)" > "$OUTPUT/build.log" 2>&1
cp ffmpeg "$OUTPUT/ffmpeg"
cp COPYING.LGPLv2.1 "$OUTPUT/COPYING.LGPLv2.1"

printf "%s" "$STAMP" > "$OUTPUT/configuration.stamp"
