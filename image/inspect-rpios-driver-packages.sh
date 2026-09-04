#!/bin/bash

# Download and extract official Raspberry Pi OS driver/firmware packages for
# comparison only. Never install a deb, run maintainer scripts, or touch /boot.
set -euo pipefail

archive=https://archive.raspberrypi.com/debian
key_fingerprint=CF8A1AF502A2AA2D763BAE7E82B129927FA3303E

fail() { printf 'RPi OS inspection failed: %s\n' "$*" >&2; exit 1; }
verify_file() {
  local file=$1 expected=$2 actual
  [[ $expected =~ ^[0-9a-f]{64}$ ]] || fail "missing or invalid SHA-256 for $file"
  actual=$(sha256sum "$file" | awk '{print $1}')
  [[ $actual == "$expected" ]] || fail "SHA-256 mismatch for $file"
}
package_field() {
  awk -v package="$1" -v key="$2: " '
    BEGIN { RS=""; FS="\n" }
    $1 == "Package: " package {
      for (i=1; i<=NF; i++) if (index($i,key)==1) { print substr($i,length(key)+1); exit }
    }
  ' "$output/Packages"
}
inspect_package() {
  local package=$1 filename expected version
  filename=$(package_field "$package" Filename)
  expected=$(package_field "$package" SHA256)
  version=$(package_field "$package" Version)
  [[ $filename == pool/*.deb && $filename != *..* ]] || fail "invalid archive filename for $package"
  printf 'Inspecting %s %s\n' "$package" "$version"
  curl -fsSL --retry 3 "$archive/$filename" -o "$output/${filename##*/}"
  verify_file "$output/${filename##*/}" "$expected"
  dpkg-deb --contents "$output/${filename##*/}" >"$output/$package.files.txt"
  mkdir -p "$output/extracted/$package" "$output/control/$package"
  dpkg-deb --extract "$output/${filename##*/}" "$output/extracted/$package"
  dpkg-deb --control "$output/${filename##*/}" "$output/control/$package"
  printf '%s\t%s\t%s\t%s\n' "$package" "$version" "$expected" "$filename" >>"$output/packages.tsv"
}
main() {
  [[ $# == 1 ]] || fail "Usage: $0 NEW_OUTPUT_DIRECTORY (Linux with curl, gpg/gpgv, gzip, sha256sum, dpkg-deb)"
  output=$1
  [[ ! -e $output ]] || fail "output already exists; choose a new inspection directory"
  for command in curl gpg gpgv gzip sha256sum dpkg-deb awk; do
    command -v "$command" >/dev/null || fail "missing inspection dependency: $command"
  done
  mkdir -p "$output/gnupg"
  output=$(cd -- "$output" && pwd)
  chmod 700 "$output/gnupg"
  curl -fsSL --retry 3 "$archive/raspberrypi.gpg.key" -o "$output/archive-key.asc"
  fingerprint=$(gpg --homedir "$output/gnupg" --show-keys --with-colons "$output/archive-key.asc" | awk -F: '$1=="fpr" {print $10; exit}')
  [[ $fingerprint == "$key_fingerprint" ]] || fail "unexpected archive signing key"
  gpg --homedir "$output/gnupg" --batch --dearmor -o "$output/keyring.gpg" "$output/archive-key.asc"
  curl -fsSL --retry 3 "$archive/dists/trixie/InRelease" -o "$output/InRelease"
  gpgv --homedir "$output/gnupg" --keyring "$output/keyring.gpg" --output "$output/Release" "$output/InRelease"
  index_path=main/binary-arm64/Packages.gz
  index_sha=$(awk -v path="$index_path" '
    /^SHA256:/ {sha=1; next}
    /^[^ ]/ {sha=0}
    sha && $3==path {print $1; exit}
  ' "$output/Release")
  curl -fsSL --retry 3 "$archive/dists/trixie/$index_path" -o "$output/Packages.gz"
  verify_file "$output/Packages.gz" "$index_sha"
  gzip -dc "$output/Packages.gz" >"$output/Packages"
  printf 'package\tversion\tsha256\tfilename\n' >"$output/packages.tsv"
  kernel_package=$(package_field linux-image-rpi-v8 Depends | grep -oE 'linux-image-[^ ,(]+')
  [[ $kernel_package == linux-image-*-rpi-v8 ]] || fail "cannot resolve the Pi 4 ARM64 kernel metapackage"
  for package in firmware-brcm80211 bluez-firmware raspi-firmware "$kernel_package"; do
    inspect_package "$package"
  done
  printf 'Verified and extracted for inspection only: %s\n' "$output"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
