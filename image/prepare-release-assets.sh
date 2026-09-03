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
readonly part_mib="${OMARCHY_RELEASE_PART_MIB:-1900}"

[[ -f $image ]] || { echo "Image not found: $image" >&2; exit 1; }
[[ $image == *.img.xz ]] || { echo "Expected an .img.xz file: $image" >&2; exit 1; }
[[ $part_mib =~ ^[0-9]+$ ]] && (( part_mib >= 1 && part_mib <= 1900 )) || {
  echo "OMARCHY_RELEASE_PART_MIB must be between 1 and 1900" >&2
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
readonly image_size="$(wc -c <"$image" | tr -d ' ')"
readonly part_bytes=$((part_mib * 1024 * 1024))
readonly image_sha="$(sha256 "$image")"

mkdir -p "$output_dir"
printf '%s  %s\n' "$image_sha" "$basename" >"$output_dir/$basename.sha256"

if (( image_size <= part_bytes )); then
  cp "$image" "$output_dir/$basename"
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

After the final checksum passes, select $basename with Raspberry Pi Imager's
"Use custom" option. The complete image SHA-256 is:

  $image_sha
EOF
