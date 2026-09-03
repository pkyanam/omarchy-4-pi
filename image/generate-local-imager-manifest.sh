#!/bin/bash

# Wrap a local Omarchy .img.xz in Raspberry Pi Imager 2.x catalog metadata so
# its customization wizard knows to write rpi-preseed.toml.

set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

if (( $# < 1 || $# > 2 )); then
  echo "Usage: $0 IMAGE.img.xz [OUTPUT.imager.json]" >&2
  exit 64
fi

input_image="$1"
[[ -f $input_image ]] || fail "Image not found: $input_image"
[[ $input_image == *.img.xz ]] || fail "Expected a compressed .img.xz image: $input_image"
command -v python3 >/dev/null || fail "python3 is required"

image_dir=$(cd -- "$(dirname -- "$input_image")" && pwd -P)
image="$image_dir/$(basename -- "$input_image")"
output=${2:-"${image%.img.xz}.imager.json"}
image_uri=$(python3 - "$image" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).as_uri())
PY
)

"$script_dir/generate-imager-catalog.sh" "$image" "$image_uri" "$output"
printf 'Created local Raspberry Pi Imager manifest:\n  %s\n' "$output"
