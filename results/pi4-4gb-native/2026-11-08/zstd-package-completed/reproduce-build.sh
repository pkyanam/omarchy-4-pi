#!/bin/bash
set -euo pipefail
# Refuses retained attempt; use a fresh prepared private directory to reproduce.
python3 /Users/preetham/Code/omarchy-4-pi/tools/pi-experiments/zstd-package-candidates.py --out /Users/preetham/Code/omarchy-4-pi/build/upstream-pi/stable-4.5/zstd-package-candidates/attempt-3072m-swap0 --build-pair sha256:277a56bbb6f54c1cc4aa16c403904a34b0a2292b64465339f9321980f60ab514 --expected-packages /Users/preetham/Code/omarchy-4-pi/build/upstream-pi/stable-4.5/zstd-package-candidates/attempt-3072m-swap0/deps-after.packages --build-memory-mib 3072 --build-swap-mib 0
