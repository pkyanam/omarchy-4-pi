#!/bin/bash
set -euo pipefail
exec > /candidate/logs/trust.log 2>&1
trap 'status=$?; for f in memory.peak memory.events cpu.stat; do cat /sys/fs/cgroup/$f > /candidate/logs/trust-$f; done; exit "$status"' EXIT
export TMPDIR=/work/tmp
python /candidate/trust.py
