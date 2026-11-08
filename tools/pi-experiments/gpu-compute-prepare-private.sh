#!/bin/bash
set -euo pipefail
exec > /evidence/dependency-prepare.log 2>&1
mkdir -p /evidence/packages /evidence/extracted
cd /evidence/packages
for name in vulkan-headers vulkan-icd-loader spirv-tools glslang; do
  original=$(pacman -Sp --print-format '%l' "$name")
  filename=${original##*/}
  url="http://mirror.archlinuxarm.org/aarch64/extra/$filename"
  printf '%s\n' "$url" >> /evidence/package-urls.txt
  curl --fail --location --max-time 120 --output "$filename" "$url"
  curl --fail --location --max-time 60 --output "$filename.sig" "$url.sig"
  pacman-key --verify "$filename.sig" "$filename"
  sha256sum "$filename" "$filename.sig"
  mkdir -p "/evidence/extracted/$name"
  tar -xf "./$filename" -C "/evidence/extracted/$name"
  cat "/evidence/extracted/$name/.PKGINFO"
done
