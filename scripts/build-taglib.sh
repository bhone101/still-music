#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v cmake >/dev/null || { echo 'CMake is required. Install it with: brew install cmake' >&2; exit 1; }
cmake -S Vendor/taglib-2.2.1 -B .build/taglib-build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_INSTALL_PREFIX="$PWD/.build/taglib" \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF \
  -DBUILD_BINDINGS=OFF -DWITH_ASF=OFF -DWITH_DSF=OFF -DWITH_MATROSKA=OFF \
  -DWITH_MOD=OFF -DWITH_RIFF=OFF -DWITH_SHORTEN=OFF -DWITH_TRUEAUDIO=OFF
cmake --build .build/taglib-build --parallel 4
cmake --install .build/taglib-build
