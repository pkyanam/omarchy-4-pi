#!/bin/bash

# Install Omarchy Quattro on an existing Arch Linux ARM aarch64 installation
# running on a Raspberry Pi 4 Model B.

set -euo pipefail

readonly checkout="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly package_output="$checkout/build-output-rpi4"
readonly rpi_profile=/etc/omarchy-rpi4.conf

install_mode=full
image_mode=0

log() {
  if command -v gum >/dev/null 2>&1; then
    gum style --bold --foreground 2 "==> $*"
  else
    printf '\033[32m==>\033[0m %s\n' "$*"
  fi
}

warn() {
  if command -v gum >/dev/null 2>&1; then
    gum style --bold --foreground 3 "Warning: $*" >&2
  else
    printf '\033[33mWarning:\033[0m %s\n' "$*" >&2
  fi
}

fail() {
  if command -v gum >/dev/null 2>&1; then
    gum style --bold --foreground 1 "Error: $*" >&2
  else
    printf '\033[31mError:\033[0m %s\n' "$*" >&2
  fi
  exit 1
}

pacman_retry() {
  local attempt=1 max_attempts=4
  # CI image builds download the complete desktop in one transaction. Give
  # intermittent community mirrors more chances while retaining every package
  # already cached by earlier attempts. Interactive installs fail sooner.
  (( image_mode == 0 )) || max_attempts=8
  while true; do
    if sudo pacman "$@"; then
      return 0
    fi
    (( attempt < max_attempts )) || return 1
    warn "Package transaction failed (attempt $attempt/$max_attempts); retrying with cached downloads."
    if (( image_mode )); then
      sleep $(( attempt * 30 ))
    else
      sleep $(( attempt * 5 ))
    fi
    ((attempt++))
  done
}

usage() {
  cat <<'USAGE'
Usage: ./install-rpi4.sh [--minimal] [--image]

Installs Omarchy Quattro on a Raspberry Pi 4 Model B already running the
official Arch Linux ARM aarch64 root filesystem.

--minimal  Install the complete Quattro desktop and system integration, but
           skip optional Omarchy applications that must be built locally.
--image    Prepare an OEM image with first-boot owner provisioning instead of
           configuring the user running this command.
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --minimal)
        install_mode=minimal
        shift
        ;;
      --image)
        image_mode=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

device_model() {
  local model_file="${OMARCHY_RPI_MODEL_PATH:-/proc/device-tree/model}"
  [[ -r $model_file ]] && tr -d '\0' <"$model_file"
}

check_preconditions() {
  (( EUID != 0 )) || fail "Run this as your regular user, not as root. It uses sudo where needed."
  [[ $(uname -m) == "aarch64" ]] || fail "This installer requires Arch Linux ARM aarch64."
  command -v pacman >/dev/null || fail "pacman is required; start from Arch Linux ARM, not Raspberry Pi OS."
  command -v sudo >/dev/null || fail "sudo is required. Install it as root before running this script."

  local model
  model=$(device_model)
  if [[ $model != *"Raspberry Pi 4 Model B"* ]]; then
    if [[ ${OMARCHY_RPI4_ALLOW_UNSUPPORTED:-0} == "1" ]]; then
      warn "Expected a Raspberry Pi 4 Model B, found '${model:-unknown hardware}'; continuing by request."
    else
      fail "Expected a Raspberry Pi 4 Model B, found '${model:-unknown hardware}'."
    fi
  fi
}

configure_arm_repositories() {
  log "Configuring Arch Linux ARM package repositories"
  sudo install -Dm644 "$checkout/default/pacman/pacman-rpi4.conf" /etc/pacman.conf
  sudo install -Dm644 "$checkout/default/pacman/mirrorlist-rpi4" /etc/pacman.d/mirrorlist
  if (( image_mode )); then
    sudo install -Dm644 "$checkout/default/pacman/mirrorlist-rpi4-image" /etc/pacman.d/mirrorlist
    sudo sed -i 's/^ParallelDownloads = .*/ParallelDownloads = 1/' /etc/pacman.conf
  fi
  sudo pacman-key --init
  sudo pacman-key --populate archlinuxarm
  pacman_retry -Syyu --needed --noconfirm git base-devel gum
}

ensure_package_sources() {
  if [[ -n ${OMARCHY_PKGS_PATH:-} && -d ${OMARCHY_PKGS_PATH:-}/pkgbuilds ]]; then
    return 0
  fi

  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-rpi4"
  local pkgs_checkout="$cache_dir/omarchy-pkgs"
  local recipe_commit
  recipe_commit=$(<"$checkout/image/omarchy-pkgs.commit")
  [[ $recipe_commit =~ ^[0-9a-f]{40}$ ]] || fail "Missing reviewed Pi package-recipe commit."
  mkdir -p "$cache_dir"

  if [[ -d $pkgs_checkout/.git ]]; then
    [[ -z $(git -C "$pkgs_checkout" status --porcelain) ]] || fail "Package recipes contain local edits; preserve them before updating."
    [[ $(git -C "$pkgs_checkout" remote get-url origin) == "https://github.com/omacom/omarchy-pkgs.git" ]] ||
      fail "Unexpected package-recipe origin."
  else
    log "Cloning Omarchy PKGBUILDs"
    git clone --depth 1 --no-checkout https://github.com/omacom/omarchy-pkgs.git "$pkgs_checkout"
  fi
  log "Using the Pi-reviewed package recipes at $recipe_commit"
  if ! git -C "$pkgs_checkout" cat-file -e "$recipe_commit^{commit}" 2>/dev/null; then
    git -C "$pkgs_checkout" fetch --depth 1 origin "$recipe_commit"
  fi
  git -C "$pkgs_checkout" checkout --detach "$recipe_commit"

  export OMARCHY_PKGS_PATH="$pkgs_checkout"
}

package_is_excluded() {
  local package="$1" excluded
  while read -r excluded; do
    [[ -n $excluded ]] || continue
    [[ $package == "$excluded" ]] && return 0
  done < <(grep -vE '^[[:space:]]*(#|$)' "$checkout/install/omarchy-rpi4-unavailable.packages")
  return 1
}

install_official_packages() {
  local package
  local -a available=()

  log "Resolving the Quattro package set against Arch Linux ARM"
  while read -r package; do
    [[ -n $package ]] || continue
    package_is_excluded "$package" && continue
    if pacman -Si "$package" >/dev/null 2>&1; then
      available+=("$package")
    fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$checkout/install/omarchy-base.packages")

  # These normally come from the ISO's secondary package list or as hard
  # dependencies of omarchy. The Pi installer has no ISO to supply them.
  available+=(
    archlinuxarm-keyring
    cloud-guest-utils
    firmware-raspberrypi
    hicolor-icon-theme
    iw
    linux-aarch64
    neovim
    openssh
    pipewire
    pipewire-alsa
    pipewire-pulse
    python
    qt6-wayland
    raspberrypi-utils
    snapper
    sudo
    vulkan-broadcom
    wf-recorder
    xdg-user-dirs
    zram-generator
  )

  log "Installing ${#available[@]} packages from Arch Linux ARM"
  pacman_retry -S --needed --noconfirm "${available[@]}"

  # Image builds have a fixed-size staging filesystem. Retaining more than a
  # gigabyte of package archives while compiling the remaining local packages
  # can exhaust that staging space even though the finished image fits.
  if (( image_mode )); then
    sudo pacman -Scc --noconfirm
  fi
}

build_recipe() {
  local package="$1" required="${2:-0}"
  local recipe="$OMARCHY_PKGS_PATH/pkgbuilds/$package"
  local workspace

  [[ -d $recipe ]] || {
    (( required == 0 )) && warn "No PKGBUILD found for optional package $package; skipping."
    (( required == 0 )) || fail "No PKGBUILD found for required package $package."
    return "$required"
  }

  workspace=$(mktemp -d)
  cp -a "$recipe/." "$workspace/"
  if (
    cd "$workspace"
    makepkg -s --noconfirm
  ); then
    local artifact
    local -a artifacts=()
    for artifact in "$workspace/$package-"*.pkg.tar.*; do
      [[ -f $artifact && $artifact != *.sig ]] && artifacts+=("$artifact")
    done
    if (( ${#artifacts[@]} )); then
      sudo pacman -U --needed --noconfirm "${artifacts[@]}"
      rm -rf "$workspace"
    elif (( required )); then
      rm -rf "$workspace"
      fail "Required ARM package $package produced no package archive."
    else
      rm -rf "$workspace"
      warn "Optional ARM package $package produced no package archive; skipping."
    fi
  else
    rm -rf "$workspace"
    if (( required )); then
      fail "Required ARM package $package failed to build."
    else
      warn "Optional ARM package $package failed to build; the desktop will continue without it."
    fi
  fi
}

install_arm_packages() {
  local package
  local -a required=(
    yay
    mise-bin
    ufw-docker
    xdg-terminal-exec
    yaru-icon-theme
    ttfx
  )
  local -a optional=(
    aether
    cliamp
    herdr
    localsend
    omacalc
    omacut
    omawrite
    omarchy-nvim
    tobi-try
    ttf-ia-writer
  )

  log "Building required ARM packages"
  for package in "${required[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || build_recipe "$package" 1
  done

  if [[ $install_mode == "full" ]]; then
    log "Building optional Omarchy applications for ARM (this can take a while on a Pi 4)"
    for package in "${optional[@]}"; do
      pacman -Q "$package" >/dev/null 2>&1 || build_recipe "$package" 0
    done
  fi
}

build_omarchy_packages() {
  log "Building the Raspberry Pi Quattro packages"
  OMARCHY_PACKAGE_OUTPUT="$package_output" "$checkout/build-packages-rpi4.sh"
}

install_omarchy_packages() {
  local artifact
  local -a built=()
  for artifact in "$package_output"/*.pkg.tar.*; do
    [[ -f $artifact && $artifact != *.sig ]] || continue
    built+=("$artifact")
  done
  (( ${#built[@]} )) || fail "No packages were built in $package_output."

  log "Installing the locally built Omarchy packages"
  sudo pacman -U --noconfirm "${built[@]}"
  source /usr/share/omarchy/default/bash/env-bootstrap
}

write_rpi_profile() {
  local encoded_checkout
  printf -v encoded_checkout '%q' "$checkout"
  printf 'OMARCHY_RPI4_SOURCE=%s\nOMARCHY_PACMAN_PROFILE=rpi4\n' "$encoded_checkout" |
    sudo tee "$rpi_profile" >/dev/null
  sudo chmod 0644 "$rpi_profile"
}

seed_user_defaults() {
  log "Seeding Quattro defaults for $USER"
  omarchy-reinstall-configs
}

stage_node_tarball() {
  local node_dist_url=${OMARCHY_NODE_DIST_URL:-https://nodejs.org/dist/latest}
  local shasums filename expected actual temporary

  [[ $node_dist_url == https://* && $node_dist_url != *'"'* &&
    $node_dist_url != *$'\r'* && $node_dist_url != *$'\n'* ]] ||
    fail "OMARCHY_NODE_DIST_URL must be a safe HTTPS URL."
  command -v curl >/dev/null || fail "curl is required to stage offline Node.js."

  log "Staging a verified ARM64 Node.js bundle for offline owner setup"
  shasums=$(curl --fail --silent --show-error --location --retry 3 \
    "$node_dist_url/SHASUMS256.txt") || fail "Could not download Node.js checksums."
  filename=$(awk '$2 ~ /^node-v[0-9][0-9.]*-linux-arm64[.]tar[.]gz$/ { print $2; exit }' <<<"$shasums")
  [[ -n $filename ]] || fail "Node.js checksums list has no Linux ARM64 archive."
  expected=$(awk -v filename="$filename" '$2 == filename { print $1; exit }' <<<"$shasums")
  [[ $expected =~ ^[0-9a-f]{64}$ ]] || fail "Node.js ARM64 checksum is missing or invalid."

  temporary=$(mktemp -d)
  if ! curl --fail --silent --show-error --location --retry 3 \
    --output "$temporary/$filename" "$node_dist_url/$filename"; then
    rm -rf "$temporary"
    fail "Could not download the Node.js ARM64 archive."
  fi
  actual=$(sha256sum "$temporary/$filename" | awk '{ print $1 }')
  if [[ $actual != "$expected" ]]; then
    rm -rf "$temporary"
    fail "Node.js ARM64 archive checksum does not match its official manifest."
  fi

  sudo install -d -m 0755 /var/lib/omarchy/provisioning/packages
  sudo find /var/lib/omarchy/provisioning/packages -maxdepth 1 -type f \
    -name 'node-v*-linux-*.tar.gz' -delete
  sudo install -m 0644 "$temporary/$filename" \
    "/var/lib/omarchy/provisioning/packages/$filename"
  rm -rf "$temporary"
}

arm_first_boot_provisioning() {
  local unit_source="$checkout/install/provisioning/omarchy-provision-owner.service"
  local grow_unit_source="$checkout/install/provisioning/omarchy-rpi4-grow-root.service"
  local grow_dependency_source="$checkout/install/provisioning/omarchy-provision-owner-rpi4.conf"
  local sddm_dependency_source="$checkout/install/provisioning/omarchy-sddm-rpi4.conf"

  stage_node_tarball

  # Install this explicitly as well as through the Omarchy package: image-mode
  # support must not depend on a future upstream PKGBUILD continuing to glob
  # every bin/ entry.
  sudo install -Dm755 "$checkout/bin/omarchy-rpi4-imager-preseed" \
    /usr/bin/omarchy-rpi4-imager-preseed
  sudo install -Dm644 "$unit_source" /etc/systemd/system/omarchy-provision-owner.service
  sudo install -Dm644 "$grow_unit_source" /etc/systemd/system/omarchy-rpi4-grow-root.service
  sudo install -Dm644 "$grow_dependency_source" \
    /etc/systemd/system/omarchy-provision-owner.service.d/10-rpi4-grow-root.conf
  sudo install -Dm644 "$sddm_dependency_source" \
    /etc/systemd/system/sddm.service.d/10-rpi4-owner-setup.conf
  sudo install -Dm644 "$checkout/install/provisioning/omarchy-avahi-rpi4.conf" \
    /etc/systemd/system/avahi-daemon.service.d/10-rpi4-owner-hostname.conf
  sudo install -d /var/lib/omarchy/provisioning /etc/systemd/system/multi-user.target.wants
  sudo touch /var/lib/omarchy/provisioning/pending \
    /var/lib/omarchy/provisioning/grow-root-pending
  sudo ln -sfn /etc/systemd/system/omarchy-provision-owner.service \
    /etc/systemd/system/multi-user.target.wants/omarchy-provision-owner.service
  sudo ln -sfn /etc/systemd/system/omarchy-rpi4-grow-root.service \
    /etc/systemd/system/multi-user.target.wants/omarchy-rpi4-grow-root.service
}

run_system_setup() {
  local -a hardware_env=(OMARCHY_PACMAN_PROFILE=rpi4)
  [[ -z ${OMARCHY_RPI_MODEL_PATH:-} ]] || hardware_env+=(OMARCHY_RPI_MODEL_PATH="$OMARCHY_RPI_MODEL_PATH")
  [[ -z ${OMARCHY_RPI_CONFIG_PATH:-} ]] || hardware_env+=(OMARCHY_RPI_CONFIG_PATH="$OMARCHY_RPI_CONFIG_PATH")

  log "Applying Raspberry Pi and Omarchy system configuration"
  if (( image_mode )); then
    sudo env "${hardware_env[@]}" omarchy-apply-system --defer-provisioning --first-install
    arm_first_boot_provisioning
    return 0
  fi

  sudo env "${hardware_env[@]}" omarchy-apply-system --install-user "$USER" --first-install

  log "Applying Omarchy user configuration"
  OMARCHY_SETUP_CONTEXT=rpi4 omarchy-provision-user --first-install
}

main() {
  parse_args "$@"
  check_preconditions
  configure_arm_repositories
  ensure_package_sources
  install_official_packages
  install_arm_packages
  build_omarchy_packages
  install_omarchy_packages
  write_rpi_profile
  (( image_mode )) || seed_user_defaults
  run_system_setup

  log "Omarchy Quattro for Raspberry Pi 4 is installed. Reboot to start the desktop."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
