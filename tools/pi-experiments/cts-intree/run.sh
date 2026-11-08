#!/bin/bash
set -euo pipefail
exec > /candidate/logs/final.log 2>&1
export TMPDIR=/work/tmp
python /candidate/final.py
