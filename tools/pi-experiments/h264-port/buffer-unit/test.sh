#!/bin/bash
set -euo pipefail
candidate_dir=$(cd "$(dirname "$0")/.." && pwd)
docker run --rm --network=none --name omarchy-h264-buffer-unit --cpus=.25 --memory=256m --memory-swap=256m \
  --mount "type=bind,src=$candidate_dir,dst=/candidate" \
  sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2 \
  bash -c 'cd /candidate; ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 python3 buffer-unit/run.py "$@"' bash "$@"
