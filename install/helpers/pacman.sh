# shellcheck shell=bash
# Pacman repository templates. Every platform has a pacman.conf and mirrorlist
# for each channel it offers, copied into place whole, as x86's always were:
# x86's in default/pacman, each ARM platform's in a directory named for it.
# Sourcing this file only defines functions; it never changes the system.

# The directory holding <platform>'s pacman-<channel>.conf and
# mirrorlist-<channel>. A channel without both files isn't offered there.
omarchy_pacman_templates() {
  if omarchy_pacman_pi_profile; then
    echo "$OMARCHY_PATH/default/pacman"
    return
  fi
  case ${1:-} in
    x86) echo "$OMARCHY_PATH/default/pacman" ;;
    aarch64 | aarch64-apple) echo "$OMARCHY_PATH/default/pacman/$1" ;;
    # Snapdragon, the N1x and the GB10 use Arch Linux ARM and Omarchy's aarch64
    # repository like any other ARM machine, so they share its templates.
    aarch64-qualcomm | aarch64-n1x | aarch64-gb10) echo "$OMARCHY_PATH/default/pacman/aarch64" ;;
    *)
      echo "Error: Unknown platform '${1:-}'." >&2
      return 1
      ;;
  esac
}

# The channel a machine takes when none is named: stable, except on Apple
# Silicon, whose machines have followed edge from the start and stay there
# unless they choose another channel.
omarchy_pacman_default_channel() {
  if omarchy_pacman_pi_profile; then
    echo rpi4
    return
  fi
  case ${1:-} in
    x86 | aarch64 | aarch64-qualcomm | aarch64-n1x | aarch64-gb10) echo stable ;;
    aarch64-apple) echo edge ;;
    *)
      echo "Error: Unknown platform '${1:-}'." >&2
      return 1
      ;;
  esac
}

# rpi4 is a repository profile, not a platform name. Image builders explicitly
# select it; installed boards retain the marker even away from a live session.
omarchy_pacman_pi_profile() {
  [[ ${OMARCHY_PACMAN_PROFILE:-} == "rpi4" || -f /etc/omarchy-rpi4.conf ]] ||
    omarchy-hw-raspberry-pi
}

# Bootstrap only reviewed public trust material, before using [omarchy]. These
# digests are from omarchy-pkgs c7a1ef7f86cccab072fb11f22564862c03f50199,
# whose PKGBUILD checks the same files. HTTPS plus fixed digests anchors trust;
# package signatures remain Required. No keyserver or unverified key import.
# The caller establishes disk-backed TMPDIR before invoking this function.
omarchy_pi_bootstrap_keyring() (
  set -euo pipefail
  local temporary file expected keyring_owned=0
  local -a elevate=()
  (( EUID == 0 )) || elevate=(sudo)
  temporary=$(mktemp -d)
  trap 'rm -rf "$temporary"' EXIT
  for file in omarchy.gpg omarchy-trusted omarchy-revoked; do
    case $file in
      omarchy.gpg) expected=f9455c60f30984d73ddebecf55a1b6dcb3afba84638c5d78130494bb828f53cfa19d393c27e43514d5847b37dcd0a5601ba39b213c2185ff153001b7221c9c8c ;;
      omarchy-trusted) expected=39767d13b783903d97f68e23100982c645356c7f7dbd9625ae41f4fa217c937f09e0f5dd8e0741f0950f2d9418a160dbce7563e1f4a4599d545e38f986fd8fb9 ;;
      omarchy-revoked) expected=cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e ;;
    esac
    curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --retry 3 \
      "https://raw.githubusercontent.com/omacom/omarchy-pkgs/c7a1ef7f86cccab072fb11f22564862c03f50199/pkgbuilds/omarchy-keyring/$file" \
      --output "$temporary/$file"
    printf '%s  %s\n' "$expected" "$temporary/$file" | sha512sum --check --status || {
      echo "Omarchy public keyring checksum failed: $file" >&2
      exit 1
    }
  done
  pacman -Q omarchy-keyring >/dev/null 2>&1 && keyring_owned=1
  for file in omarchy.gpg omarchy-trusted omarchy-revoked; do
    "${elevate[@]}" install -Dm644 "$temporary/$file" "/usr/share/pacman/keyrings/$file"
  done
  "${elevate[@]}" pacman-key --init
  "${elevate[@]}" pacman-key --populate archlinuxarm omarchy
  # Trust is now in pacman's local public keyring. Leave the conventional
  # keyring paths for the signed package to own, avoiding unowned-file conflicts
  # on fresh image AND direct-install paths. Never remove package-owned files.
  if (( keyring_owned == 0 )); then
    for file in omarchy.gpg omarchy-trusted omarchy-revoked; do
      "${elevate[@]}" rm -f "/usr/share/pacman/keyrings/$file"
    done
  fi
)
