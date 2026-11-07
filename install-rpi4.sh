#!/bin/bash

# Install Omarchy Quattro on an existing Arch Linux ARM aarch64 installation
# running on a Raspberry Pi 4 Model B.

set -euo pipefail

checkout=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly checkout
readonly package_output="$checkout/build-output-rpi4"
readonly rpi_profile=/etc/omarchy-rpi4.conf
source "$checkout/install/helpers/rpi4-packages.sh"

install_mode=full
image_mode=0
resume_mode=0
install_identity=""
install_phase=missing

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
Usage: ./install-rpi4.sh [--minimal] [--image] [--resume]

Installs Omarchy Quattro on a Raspberry Pi 4 Model B already running the
official Arch Linux ARM aarch64 root filesystem.

--minimal  Install the complete Quattro desktop and system integration, but
           skip the explicitly optional application set. Required migration apps
           are installed as signed ARM binaries in both modes.
--image    Prepare an OEM image with first-boot owner provisioning instead of
           configuring the user running this command.
--resume   Retry an interrupted fresh installation using the same user,
           unchanged source checkout and original --minimal/--image options.
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
      --resume)
        resume_mode=1
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

install_checkpoint() {
  sudo bash "$checkout/install/helpers/rpi4-install-state.sh" "$1" "$install_identity"
}

existing_install() {
  [[ -e $rpi_profile || -e /var/lib/omarchy/provisioning ||
    -e /usr/share/omarchy || -e $HOME/.config/omarchy ]]
}

prepare_install_request() {
  local source_commit
  source_commit=$(git -C "$checkout" rev-parse HEAD) || fail "Installation requires a Git checkout."
  git -C "$checkout" diff --quiet HEAD -- || fail "Commit or preserve tracked source edits before installing."
  install_identity=$(printf '%s\0' 1 "$UID" "$USER" "$HOME" "$checkout" "$source_commit" "$install_mode" "$image_mode" | sha256sum | cut -d' ' -f1)
  install_phase=$(install_checkpoint inspect) || fail "Could not validate the fresh-install checkpoint."
  if [[ $install_phase == "missing" ]]; then
    (( resume_mode == 0 )) || fail "No interrupted fresh installation exists to resume."
    # A receipt is created only after this check; a completed or legacy system
    # cannot opt into a fresh-install replay by passing --resume.
    if existing_install; then
      fail "Omarchy is already provisioned. Use 'omarchy update' on a stable-4.5 Pi installation. For a legacy rolling Pi, back up personal data and flash the complete 4.5 candidate to spare media; an in-place repo switch or partial downgrade is not supported."
    fi
  elif [[ $install_phase == "complete" ]]; then
    fail "This fresh installation is complete. Use 'omarchy update'; installation setup cannot be replayed."
  else
    (( resume_mode )) || fail "A fresh installation was interrupted. Rerun this unchanged checkout with --resume and the original --minimal/--image options."
    install_phase=$(install_checkpoint resume) || fail "The interrupted installation does not match this request."
  fi
}

check_preconditions() {
  (( EUID != 0 )) || fail "Run this as your regular user, not as root. It uses sudo where needed."
  "$checkout/bin/omarchy-hw-aarch64" || fail "This installer requires Arch Linux ARM aarch64."
  command -v pacman >/dev/null || fail "pacman is required; start from Arch Linux ARM, not Raspberry Pi OS."
  command -v sudo >/dev/null || fail "sudo is required. Install it as root before running this script."
  command -v git >/dev/null || fail "git is required to identify the installation source."

  local model
  model=$(device_model)
  if [[ $model != *"Raspberry Pi 4 Model B"* ]]; then
    if [[ ${OMARCHY_RPI4_ALLOW_UNSUPPORTED:-0} == "1" ]]; then
      warn "Expected a Raspberry Pi 4 Model B, found '${model:-unknown hardware}'; continuing by request."
    else
      fail "Expected a Raspberry Pi 4 Model B, found '${model:-unknown hardware}'."
    fi
  fi
  prepare_install_request
}

prepare_build_environment() {
  source "$checkout/default/pi/build-environment.sh"
  omarchy_pi_prepare_build install
  trap omarchy_pi_cleanup_build EXIT
}

configure_arm_repositories() {
  log "Configuring the signed released stable ARM package closure"
  source "$checkout/install/helpers/pacman.sh"
  # Trust precedes any sync against [omarchy]; never disable signatures.
  omarchy_pi_bootstrap_keyring
  sudo install -Dm644 "$checkout/default/pacman/pacman-rpi4.conf" /etc/pacman.conf
  sudo install -Dm644 "$checkout/default/pacman/mirrorlist-rpi4" /etc/pacman.d/mirrorlist
  if (( image_mode )); then
    sudo sed -i 's/^ParallelDownloads = .*/ParallelDownloads = 1/' /etc/pacman.conf
  fi
  # A fresh ALARM rootfs may be newer than this closure. Align the WHOLE fresh
  # system, never selected libraries. check_preconditions excludes owned installs.
  pacman_retry -Syyuu --needed --noconfirm git base-devel gum python
}

check_existing_package_policy() {
  local profile=${OMARCHY_RPI4_PROFILE:-$rpi_profile}
  if [[ -f $profile ]] && ! grep -qx 'OMARCHY_RPI4_PACKAGE_POLICY=stable-4.5' "$profile"; then
    # An old installed updater can source these leaves after fetching this
    # checkout. Stop it before recipe/package changes as well as guarding the
    # new top-level updater. Its earlier source fetch cannot be undone here.
    fail "Legacy rolling ALARM profile: no automatic stable transition is supported. Back up personal data and flash the complete 4.5 Pi candidate to spare media; retain the old card for recovery. No repositories or packages were changed."
  fi
}

ensure_package_sources() {
  check_existing_package_policy
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-rpi4"
  local pkgs_checkout="$cache_dir/omarchy-pkgs"
  local recipe_commit
  recipe_commit=$(<"$checkout/image/omarchy-pkgs.commit")
  [[ $recipe_commit =~ ^[0-9a-f]{40}$ ]] || fail "Missing reviewed Pi package-recipe commit."
  if [[ -n ${OMARCHY_PKGS_PATH:-} ]]; then
    pkgs_checkout=${OMARCHY_PKGS_PATH%/pkgbuilds}
    omarchy_pi_verify_recipes "$pkgs_checkout" "$recipe_commit" || fail "Unreviewed explicit package recipes."
    export OMARCHY_PKGS_PATH="$pkgs_checkout"
    return 0
  fi
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

  omarchy_pi_verify_recipes "$pkgs_checkout" "$recipe_commit" || fail "Package recipe provenance failed."
  export OMARCHY_PKGS_PATH="$pkgs_checkout"
}

install_official_packages() {
  check_existing_package_policy
  local resolved omissions
  local -a selected=()
  log "Resolving the complete Pi $install_mode package contract"
  # Capture status before reading the plan: process substitution would hide an
  # unresolved required runtime and allow the core replacement to proceed.
  omissions=$(mktemp)
  if resolved=$(python3 "$checkout/install/helpers/rpi4-packages.py" "$checkout" "$install_mode" 2>"$omissions"); then
    cat "$omissions" >&2
  else
    cat "$omissions" >&2
    rm -f "$omissions"
    fail "Required Pi packages did not resolve; no core packages were replaced."
  fi
  [[ -n $resolved ]] || fail "The Pi package plan is empty."
  mapfile -t selected <<<"$resolved"
  pacman_retry -S --needed --noconfirm "${selected[@]}"
  python3 "$checkout/install/helpers/rpi4-packages.py" "$checkout" "$install_mode" --verify >/dev/null ||
    fail "Installed Pi runtime does not match the selected stable binaries."
  sudo install -d /var/lib/omarchy
  printf '%s\n' "$resolved" | sudo tee /var/lib/omarchy/rpi4-package-plan >/dev/null
  sudo install -m0644 "$omissions" /var/lib/omarchy/rpi4-package-omissions
  rm -f "$omissions"
}

# Compatibility leaf for callers of the old installer. Runtime packages now
# come from verified binaries, and already-installed versions are reconciled.
install_arm_packages() {
  install_official_packages
}

build_omarchy_packages() {
  log "Building the Raspberry Pi Quattro packages"
  OMARCHY_PACKAGE_OUTPUT="$package_output" "$checkout/build-packages-rpi4.sh"
}

install_omarchy_packages() {
  omarchy_pi_verify_artifacts "$package_output" || fail "Incomplete or stale Pi core artifact set."
  log "Installing the complete locally built Pi core/settings pair"
  sudo env OMARCHY_RPI4_CORE_INSTALL=1 OMARCHY_UPDATE_PACMAN=1 \
    pacman -U --noconfirm "${omarchy_pi_artifacts[@]}"
  omarchy_pi_verify_installed_artifacts || fail "The Pi core artifact set did not install completely."
  source /usr/share/omarchy/default/bash/env-bootstrap
}

write_rpi_profile() {
  local encoded_checkout
  printf -v encoded_checkout '%q' "$checkout"
  printf 'OMARCHY_RPI4_SOURCE=%s\nOMARCHY_PACMAN_PROFILE=rpi4\nOMARCHY_RPI4_PACKAGE_POLICY=stable-4.5\n' "$encoded_checkout" |
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
  # Standalone --image installs do not run the full disk-image manifest writer.
  # Keep the verified download identity beside the bundle for offline setup.
  python3 -I - "$filename" "$expected" >"$temporary/node-bundle.json" <<'PY'
import json
import sys
print(json.dumps({"node_bundle": {"filename": sys.argv[1], "sha256": sys.argv[2]}}))
PY
  sudo install -m 0644 "$temporary/node-bundle.json" \
    /var/lib/omarchy/provisioning/packages/node-bundle.json
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
  OMARCHY_SETUP_CONTEXT=iso-chroot omarchy-provision-user --first-install
}

main() {
  parse_args "$@"
  local lock_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-rpi4" install_lock
  mkdir -p "$lock_dir"
  exec {install_lock}>"$lock_dir/installer.lock"
  flock -n "$install_lock" || fail "Another Pi installation is running for this user."
  check_preconditions
  prepare_build_environment
  if [[ $install_phase == "missing" ]]; then
    install_checkpoint begin
  fi
  configure_arm_repositories
  ensure_package_sources
  install_official_packages
  build_omarchy_packages
  install_omarchy_packages
  write_rpi_profile
  if (( image_mode == 0 )) && [[ $install_phase != "seeded" ]]; then
    seed_user_defaults
    install_checkpoint seeded
  fi
  run_system_setup
  install_checkpoint complete

  log "Omarchy Quattro for Raspberry Pi 4 is installed. Reboot to start the desktop."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
