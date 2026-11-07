#!/bin/bash

# Stage a flashable image for GitHub Releases. Images larger than GitHub's
# per-asset limit are split into portable, independently checksummed parts.

set -euo pipefail

if (($# != 2)); then
  echo "Usage: $0 IMAGE.img.xz OUTPUT_DIR" >&2
  exit 1
fi

readonly image="$1"
readonly output_dir="$2"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# GitHub accepts release assets smaller than 2 GiB. Keep an 8 MiB safety
# margin while avoiding needless splitting of maximum-compressed Pi images.
readonly part_mib="${OMARCHY_RELEASE_PART_MIB:-2040}"

[[ -f $image ]] || { echo "Image not found: $image" >&2; exit 1; }
[[ $image == *.img.xz ]] || { echo "Expected an .img.xz file: $image" >&2; exit 1; }
[[ $part_mib =~ ^[0-9]+$ ]] && (( part_mib >= 1 && part_mib <= 2040 )) || {
  echo "OMARCHY_RELEASE_PART_MIB must be between 1 and 2040" >&2
  exit 1
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

readonly basename="${image##*/}"
image_size="$(wc -c <"$image" | tr -d ' ')"
readonly image_size
readonly part_bytes=$((part_mib * 1024 * 1024))
image_sha="$(sha256 "$image")"
readonly image_sha

mkdir -p "$output_dir"
[[ $(cd -- "$(dirname -- "$image")" && pwd -P)/${image##*/} != "$(cd -- "$output_dir" && pwd -P)/${image##*/}" ]] || {
  echo "Release staging directory must be separate from the source image directory." >&2
  exit 1
}
printf '%s  %s\n' "$image_sha" "$basename" >"$output_dir/$basename.sha256"
catalog="${image%.img.xz}.os-list.json"
catalog_name="${basename%.img.xz}.os-list.json"
# A repeated staging attempt must not keep a whole image or a dangling catalog
# from an earlier direct/split run. Remove only assets belonging to this image.
rm -f "$output_dir/$basename" "$output_dir/$catalog_name"
if [[ -f $output_dir/os-list.json ]]; then
  python3 - "$output_dir/os-list.json" "$basename" <<'PY'
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit
path = Path(sys.argv[1])
if any(Path(unquote(urlsplit(item["url"]).path)).name == sys.argv[2] for item in json.loads(path.read_text())["os_list"]):
  path.unlink()
PY
fi

if (( image_size <= part_bytes )); then
  cp "$image" "$output_dir/$basename"
  if [[ -f $catalog ]]; then
    "$script_dir/validate-imager-catalog.sh" "$catalog" "$output_dir"
    cp "$catalog" "$output_dir/$catalog_name"
    cp "$catalog" "$output_dir/os-list.json"
  fi
  exit 0
fi

find "$output_dir" -maxdepth 1 -type f -name "$basename.part-*" -delete
split -b "${part_mib}m" -d -a 2 "$image" "$output_dir/$basename.part-"

: >"$output_dir/$basename.parts.sha256"
for part in "$output_dir/$basename.part-"*; do
  printf '%s  %s\n' "$(sha256 "$part")" "${part##*/}" \
    >>"$output_dir/$basename.parts.sha256"
done

cat >"$output_dir/$basename.REASSEMBLE.txt" <<EOF
This image exceeded GitHub Releases' per-file limit, so it is published in
numbered parts. Download every $basename.part-* file into one directory.

macOS:
  shasum -a 256 -c $basename.parts.sha256
  cat $basename.part-* > $basename
  shasum -a 256 -c $basename.sha256

Linux:
  sha256sum -c $basename.parts.sha256
  cat $basename.part-* > $basename
  sha256sum -c $basename.sha256

After the final checksum passes, preserve Imager's account/Wi-Fi/SSH wizard
by using this repository's local catalog flow (Raspberry Pi Imager 2.0.11+):

  image/generate-local-imager-manifest.sh "$basename"

On macOS, open the image with the customization-aware launcher:

  image/open-in-rpi-imager-macos.sh "$basename"

On Linux, launch Imager with --repo pointing at the generated local catalog.
No remote catalog is published for the split image: its whole-image URL would
not be downloadable. The complete image SHA-256 is:

  $image_sha
EOF
