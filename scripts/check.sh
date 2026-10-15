#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-taglib.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift run --scratch-path .build StillChecks "$@"
