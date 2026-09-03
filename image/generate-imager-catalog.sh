#!/bin/bash

# Generate a Raspberry Pi Imager 2.x OS-list entry for a finished .img.xz.

set -euo pipefail

if (($# != 3)); then
  echo "Usage: $0 IMAGE.img.xz DOWNLOAD_URL OUTPUT.json" >&2
  exit 1
fi

readonly image="$1"
readonly download_url="$2"
readonly output="$3"
readonly repo_url=https://github.com/pkyanam/omarchy-4-pi

[[ -f $image ]] || { echo "Image not found: $image" >&2; exit 1; }
command -v xz >/dev/null || { echo "xz is required" >&2; exit 1; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | awk '{print $1}'
  else
    shasum -a 256 "$@" | awk '{print $1}'
  fi
}

download_size=$(wc -c <"$image" | tr -d ' ')
extract_size=$(xz --robot --list "$image" | awk -F '\t' '$1=="totals"{print $5}')
download_sha=$(sha256 "$image")
if command -v sha256sum >/dev/null 2>&1; then
  extract_sha=$(xz --decompress --stdout "$image" | sha256sum | awk '{print $1}')
else
  extract_sha=$(xz --decompress --stdout "$image" | shasum -a 256 | awk '{print $1}')
fi
release_date=$(date -u +%Y-%m-%d)
icon_url="https://raw.githubusercontent.com/pkyanam/omarchy-4-pi/main/docs/assets/imager-icon.svg"

cat >"$output" <<EOF
{
  "imager": {
    "devices": [
      {
        "name": "Raspberry Pi 4",
        "description": "Raspberry Pi 4 Model B, 400, and Compute Module 4 / 4S",
        "icon": "https://downloads.raspberrypi.com/imager/icons/RPi_4.png",
        "tags": ["pi4-64bit", "pi4-32bit"],
        "matching_type": "inclusive",
        "architecture": "armv8",
        "capabilities": []
      }
    ]
  },
  "os_list": [
    {
      "name": "Omarchy 4 Pi",
      "description": "Omarchy Quattro for Raspberry Pi 4 — Hyprland, Quickshell, and tiny-board energy.",
      "url": "$download_url",
      "icon": "$icon_url",
      "website": "$repo_url",
      "release_date": "$release_date",
      "extract_size": $extract_size,
      "extract_sha256": "$extract_sha",
      "image_download_size": $download_size,
      "image_download_sha256": "$download_sha",
      "devices": ["pi4-64bit"],
      "init_format": "rpi-preseed",
      "architecture": "armv8"
    }
  ]
}
EOF
