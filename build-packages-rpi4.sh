#!/bin/bash

# Build the architecture-independent Omarchy packages for Raspberry Pi 4.
# The source tree is filtered so the packages do not install or depend on the
# x86 Limine/mkinitcpio boot stack used by the Omarchy ISO.

set -euo pipefail

readonly checkout="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly output_dir="${OMARCHY_PACKAGE_OUTPUT:-$checkout/build-output-rpi4}"
readonly source_cache="${OMARCHY_PACKAGE_SRCDEST:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-rpi4/sources}"
readonly packages=(
  omarchy-keyring
  ttf-jetbrains-mono-nerd-basic
  omarchy-settings
  omarchy
)
readonly boot_dependencies=(
  limine
  limine-mkinitcpio-hook
  limine-snapper-sync
)

log() { printf '\033[32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  [[ -z ${build_root:-} ]] || rm -rf "$build_root"
}

find_pkgbuilds() {
  local candidate
  for candidate in \
    "${OMARCHY_PKGS_PATH:-}/pkgbuilds" \
    "${OMARCHY_PKGS_PATH:-}" \
    "$checkout/../omarchy-pkgs/pkgbuilds" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-rpi4/omarchy-pkgs/pkgbuilds"; do
    [[ -n $candidate && -d $candidate ]] || continue
    (cd -- "$candidate" && pwd)
    return 0
  done
  return 1
}

strip_boot_dependencies() {
  local pkgbuild="$1" dependency
  for dependency in "${boot_dependencies[@]}"; do
    sed -i "/^[[:space:]]*'${dependency}'[[:space:]]*$/d" "$pkgbuild"
  done
}

strip_boot_settings_entries() {
  local pkgbuild="$1"
  sed -i \
    -e '/etc\/mkinitcpio\.conf\.d\/omarchy_hooks\.conf/d' \
    -e '/etc\/mkinitcpio\.conf\.d\/thunderbolt_module\.conf/d' \
    -e '/etc\/limine-entry-tool\.d\/omarchy-defaults\.conf/d' \
    -e '/etc\/limine-entry-tool\.d\/omarchy-uki\.conf/d' \
    "$pkgbuild"
}

prepare_source_tree() {
  source_tree="$build_root/source"
  mkdir -p "$source_tree"
  cp -a "$checkout/." "$source_tree/"
  rm -rf "$source_tree/.git" \
    "$source_tree/build-output-rpi4" \
    "$source_tree/config/autostart/limine-snapper-notify.desktop" \
    "$source_tree/etc/limine-entry-tool.d"
  rm -f "$source_tree/etc/mkinitcpio.conf.d/omarchy_hooks.conf" \
    "$source_tree/etc/mkinitcpio.conf.d/thunderbolt_module.conf"
}

install_build_dependencies() {
  local pkgbuild_source="$1" package
  local -a build_dependencies=()
  for package in "${packages[@]}"; do
    while read -r dependency; do
      [[ -n $dependency ]] && build_dependencies+=("$dependency")
    done < <(sed -n '/^makedepends=(/,/^)/p' "$pkgbuild_source/$package/PKGBUILD" |
      sed '1d;$d' | tr -d "'\"" | tr -d ' ')
  done

  local -a missing=()
  mapfile -t missing < <(pacman -T "${build_dependencies[@]}" || true)
  # These packages exist only to compile the four local artifacts. Mark them as
  # dependencies so the image factory can remove any that are no longer needed
  # after the finished packages are installed.
  (( ${#missing[@]} == 0 )) || sudo pacman -S --asdeps --needed --noconfirm "${missing[@]}"
}

build_package() {
  local package="$1" pkgbuild_source="$2"
  local package_dir="$build_root/$package" artifact
  local -a built=()

  log "Building $package"
  cp -a "$pkgbuild_source/$package" "$package_dir"
  if [[ $package == "omarchy" ]]; then
    strip_boot_dependencies "$package_dir/PKGBUILD"
  elif [[ $package == "omarchy-settings" ]]; then
    strip_boot_settings_entries "$package_dir/PKGBUILD"
  fi

  (
    cd "$package_dir"
    SRCDEST="$source_cache" OMARCHY_SRC="$source_tree" \
      makepkg --force --noconfirm --nodeps --skipinteg
  )

  for artifact in "$package_dir"/*.pkg.tar.*; do
    [[ -f $artifact && $artifact != *.sig ]] || continue
    built+=("$artifact")
  done
  (( ${#built[@]} )) || fail "$package produced no package archive."
  mv -- "${built[@]}" "$output_dir/"
}

main() {
  [[ $(uname -m) == "aarch64" ]] || fail "Run this builder on the Raspberry Pi's aarch64 system."
  (( EUID != 0 )) || fail "Run this as a regular user, not as root."
  command -v makepkg >/dev/null || fail "makepkg is required (install base-devel)."

  local pkgbuild_source package artifact
  pkgbuild_source=$(find_pkgbuilds) || fail "No omarchy-pkgs checkout found; set OMARCHY_PKGS_PATH."
  for package in "${packages[@]}"; do
    [[ -d $pkgbuild_source/$package ]] || fail "$pkgbuild_source/$package is missing."
  done

  install_build_dependencies "$pkgbuild_source"
  build_root=$(mktemp -d)
  trap cleanup EXIT
  prepare_source_tree
  mkdir -p "$output_dir" "$source_cache"
  for artifact in "$output_dir"/*.pkg.tar.*; do
    [[ -f $artifact ]] && rm -f -- "$artifact"
  done
  for package in "${packages[@]}"; do
    build_package "$package" "$pkgbuild_source"
  done

  log "Built Raspberry Pi packages in $output_dir"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
