#!/bin/bash

# Build the architecture-independent Omarchy packages for Raspberry Pi 4.
# The source tree is filtered so the packages do not install or depend on the
# x86 Limine/mkinitcpio boot stack used by the Omarchy ISO.

set -euo pipefail

checkout="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly checkout
readonly output_dir="${OMARCHY_PACKAGE_OUTPUT:-$checkout/build-output-rpi4}"
source_cache=""
source "$checkout/install/helpers/rpi4-packages.sh"
readonly packages=("${omarchy_pi_core_packages[@]}")
readonly boot_dependencies=(
  limine
  limine-mkinitcpio-hook
  limine-snapper-sync
)

log() { printf '\033[32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  [[ -z ${build_root:-} ]] || rm -rf "$build_root"
  omarchy_pi_cleanup_build
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

adapt_recipe() {
  local package=$1 pkgbuild=$2
  if [[ $package == "omarchy" || $package == "omarchy-settings" ]]; then
    # The reviewed recipe already has an explicit OMARCHY_SRC mechanism with
    # empty source/checksum arrays. It does not require --skipinteg.
    sed -i -e "s/^pkgver=.*/pkgver=$omarchy_pi_core_version/" \
      -e 's/^pkgrel=.*/pkgrel=1/' "$pkgbuild"
  fi
  if [[ $package == "omarchy" ]]; then
    strip_boot_dependencies "$pkgbuild"
    # Pi policy deliberately excludes intro videos and uses static defaults.
    sed -i "/^[[:space:]]*'omarchy-themes-intros'[[:space:]]*$/d" "$pkgbuild"
    cat >>"$pkgbuild" <<'RECIPE'

# Pi runtime prerequisites must precede local core replacement and migrations.
depends+=('mise-bin>=2026.10.11' 'hyprland=0.56.2-7'
  'omarchy-hyprland-titlebars=0.2.2-2' 'quickshell=0.3.2.r7.g2b4501a-1')
RECIPE
  elif [[ $package == "omarchy-settings" ]]; then
    # Keep the released runtime-profile checks and sudo helper/hook ownership,
    # then filter only the installed Pi payload. Removing the source fragments
    # first would invalidate the upstream package's ARM HOOKS self-check.
    sed -i 's/^package() {/_omarchy_upstream_package() {/' "$pkgbuild"
    cat >>"$pkgbuild" <<'RECIPE'

package() {
  _omarchy_upstream_package
  rm -rf "$pkgdir/etc/mkinitcpio.conf.d" "$pkgdir/etc/limine-entry-tool.d" \
    "$pkgdir/etc/systemd/oomd.conf.d" \
    "$pkgdir/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf"
  rm -f "$pkgdir/etc/systemd/zram-generator.conf" \
    "$pkgdir/etc/tmpfiles.d/omarchy-zswap.conf" \
    "$pkgdir/etc/modprobe.d/omarchy-usb-autosuspend.conf"
  # Pi's app.slice and zram settings are applied by its performance helper.
  rm -f "$pkgdir/usr/lib/systemd/user/app.slice.d/10-oomd.conf"
  # Preserve networking and inotify policy, but not upstream reclaim/writeback
  # assumptions that conflict with the Pi's half-RAM zram and SD-card budget.
  local sysctl
  for sysctl in "$pkgdir"/etc/sysctl.d/*.conf; do
    [[ -f $sysctl ]] || continue
    sed -i '/^[[:space:]]*vm[.]/d' "$sysctl"
  done
  # The original recipe's backup array contains boot files removed above.
  local path retained=()
  for path in "${backup[@]}"; do
    [[ ! -f $pkgdir/$path ]] || retained+=("$path")
  done
  backup=("${retained[@]}")
  install -d "$pkgdir/usr/share/libalpm/hooks"
  cat >"$pkgdir/usr/share/libalpm/hooks/00-omarchy-rpi4-core-guard.hook" <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = omarchy
Target = omarchy-settings
Target = omarchy-dev
Target = omarchy-settings-dev

[Action]
Description = Protect locally adapted Raspberry Pi core packages
When = PreTransaction
Exec = /usr/bin/omarchy-update-rpi4-guard transaction
AbortOnFail
NeedsTargets
HOOK
}
RECIPE
  fi
}

prepare_source_tree() {
  source_tree="$build_root/source"
  mkdir -p "$source_tree"
  # Do not copy multi-gigabyte image artifacts or Git history onto the Pi's
  # staging filesystem merely to remove them afterward. Preserve working edits.
  tar -C "$checkout" --exclude='./.git' --exclude='./build' \
    --exclude='./build-output-rpi4' -cf - . | tar -xf - -C "$source_tree"
  rm -rf "$source_tree/.git" \
    "$source_tree/build-output-rpi4" \
    "$source_tree/config/autostart/limine-snapper-notify.desktop" \
    "$source_tree/etc/limine-entry-tool.d"
  printf '%s\n' "$omarchy_pi_core_version" >"$source_tree/version"

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
  local package_dir="$build_root/$package" artifact artifact_list
  local -a built=()

  log "Building $package"
  cp -a "$pkgbuild_source/$package" "$package_dir"
  adapt_recipe "$package" "$package_dir/PKGBUILD"

  artifact_list=$(
    cd "$package_dir"
    SRCDEST="$source_cache" OMARCHY_SRC="$source_tree" \
      makepkg --config "$OMARCHY_PI_MAKEPKG_CONF" --packagelist
  ) || fail "Could not determine $package artifact paths."

  (
    cd "$package_dir"
    SRCDEST="$source_cache" OMARCHY_SRC="$source_tree" \
      makepkg --config "$OMARCHY_PI_MAKEPKG_CONF" --force --noconfirm --nodeps
  )

  [[ -n $artifact_list ]] || fail "$package declared no package archive."
  mapfile -t built <<<"$artifact_list"
  for artifact in "${built[@]}"; do
    [[ -f $artifact && $artifact != *.sig ]] || fail "$package did not produce $artifact."
  done
  # --packagelist honors an explicit caller PKGDEST too. Copy its exact outputs
  # without moving or globbing unrelated archives out of that caller directory.
  for artifact in "${built[@]}"; do
    if [[ ! $artifact -ef $output_dir/${artifact##*/} ]]; then
      cp -- "$artifact" "$output_dir/"
    fi
    built_artifacts+=("$output_dir/${artifact##*/}")
  done

}

main() {
  "$checkout/bin/omarchy-hw-aarch64" || fail "Run this builder on the Raspberry Pi's aarch64 system."
  (( EUID != 0 )) || fail "Run this as a regular user, not as root."
  command -v makepkg >/dev/null || fail "makepkg is required (install base-devel)."

  local pkgbuild_source pkgbuild_repo package
  pkgbuild_source=$(find_pkgbuilds) || fail "No omarchy-pkgs checkout found; set OMARCHY_PKGS_PATH."
  pkgbuild_repo=${pkgbuild_source%/pkgbuilds}
  for package in "${packages[@]}"; do
    [[ -d $pkgbuild_source/$package ]] || fail "$pkgbuild_source/$package is missing."
  done

  omarchy_pi_verify_recipes "$pkgbuild_repo" "$(<"$checkout/image/omarchy-pkgs.commit")" ||
    fail "The builder requires the exact clean reviewed recipe checkout."
  source "$checkout/default/pi/build-environment.sh"
  omarchy_pi_prepare_build core
  trap cleanup EXIT
  source_cache=${OMARCHY_PACKAGE_SRCDEST:-$OMARCHY_PI_BUILD_CACHE/sources}
  if [[ -n ${OMARCHY_PACKAGE_SRCDEST:-} ]]; then
    printf 'SRCDEST=%q\n' "$source_cache" >>"$OMARCHY_PI_MAKEPKG_CONF"
  fi
  install_build_dependencies "$pkgbuild_source"
  build_root=$(mktemp -d)
  prepare_source_tree
  mkdir -p "$output_dir" "$source_cache"
  omarchy_pi_check_build_storage "$source_cache"
  git -C "$pkgbuild_repo" rev-parse HEAD >"$output_dir/omarchy-pkgs.commit" ||
    fail "The omarchy-pkgs source must be a Git checkout for provenance."
  built_artifacts=()
  for package in "${packages[@]}"; do
    build_package "$package" "$pkgbuild_source"
  done

  omarchy_pi_verify_artifacts "$output_dir" "${built_artifacts[@]}" || fail "The built Pi core artifact set is incomplete or stale."
  # Consumers use exactly this completed build, not stale/unrelated files in a
  # caller-owned PKGDEST/output directory. Never delete those caller archives.
  printf '%s\n' "${built_artifacts[@]##*/}" >"$output_dir/omarchy-pi-artifacts.list"
  log "Built Raspberry Pi packages in $output_dir"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
