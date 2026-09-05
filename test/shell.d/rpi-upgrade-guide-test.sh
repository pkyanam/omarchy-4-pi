#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
export ROOT
python3 "$ROOT/test/shell.d/rpi-upgrade-guide-fixture.py"
