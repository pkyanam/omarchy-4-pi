#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
require_command git
export ROOT
export RPI_TEST_BASH=$BASH
python3 "$ROOT/test/shell.d/rpi-upgrade-guide-fixture.py"
