#!/bin/bash

# Parse the shipped owner configuration with the image's own ARM64 Hyprland
# binary while the factory chroot is still mounted. This catches Lua, module,
# and dynamic-link failures without requiring a DRM device.

set -euo pipefail

root="${1:-}"
verify_user="${2:-omarchy-builder}"
chroot_command="${OMARCHY_CHROOT_COMMAND:-chroot}"
relative_work=/tmp/omarchy-rpi4-hyprland-verify
work="$root$relative_work"
receipt="$root/usr/share/omarchy-rpi4/hyprland-config-verified"

[[ -n $root && -d $root ]] || {
  echo "Usage: $0 ROOT_MOUNT [IMAGE_USER]" >&2
  exit 64
}
[[ -f $root/etc/skel/.config/hypr/hyprland.lua ]] || {
  echo "Error: the image has no staged owner Hyprland configuration." >&2
  exit 1
}
[[ -x $root/usr/bin/Hyprland ]] || {
  echo "Error: the image has no executable Hyprland binary." >&2
  exit 1
}

cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT INT TERM
cleanup
mkdir -p "$work/home/.config" "$work/runtime" "$work/state" "$work/cache"
cp -a "$root/etc/skel/.config/hypr" "$work/home/.config/hypr"
printf 'Raspberry Pi 4 Model B Rev 1.5\0' >"$work/pi-model"
chmod 700 "$work/runtime"

# Ownership changes happen inside the image, keeping this helper testable on a
# non-root development host while matching the factory's chroot boundary.
"$chroot_command" "$root" chown -R "$verify_user:$verify_user" "$relative_work"

run_hyprland() {
  "$chroot_command" "$root" runuser -u "$verify_user" -- \
    env \
      HOME="$relative_work/home" \
      USER="$verify_user" \
      LOGNAME="$verify_user" \
      XDG_CONFIG_HOME="$relative_work/home/.config" \
      XDG_STATE_HOME="$relative_work/state" \
      XDG_CACHE_HOME="$relative_work/cache" \
      XDG_RUNTIME_DIR="$relative_work/runtime" \
      OMARCHY_PATH=/usr/share/omarchy \
      OMARCHY_RPI_MODEL_PATH="$relative_work/pi-model" \
      bash -c "cd \"\$HOME\" && exec \"\$@\"" bash "$@"
}

version=$(run_hyprland /usr/bin/Hyprland --version | sed -n '1p')
[[ -n $version ]] || {
  echo "Error: Hyprland did not report its version." >&2
  exit 1
}

status=0
output=$(run_hyprland /usr/bin/Hyprland --verify-config \
  --config "$relative_work/home/.config/hypr/hyprland.lua" 2>&1) || status=$?
printf '%s\n' "$output"
(( status == 0 )) || exit "$status"
grep -qx 'config ok' <<<"$output" || {
  echo "Error: Hyprland exited without confirming a valid configuration." >&2
  exit 1
}

install -d "${receipt%/*}"
printf 'config=/etc/skel/.config/hypr/hyprland.lua\nversion=%s\nprofile=Raspberry Pi 4 Model B\n' \
  "$version" >"$receipt"
