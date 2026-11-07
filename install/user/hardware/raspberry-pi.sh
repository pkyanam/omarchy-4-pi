# shellcheck shell=bash
# Fresh accounts only. Re-running finalization or a package update must never
# restore toggles an owner removed, or change their theme, dock, or font.
if omarchy-hw-raspberry-pi && [[ ${OMARCHY_SETUP_CONTEXT:-runtime} == "iso-chroot" || ${OMARCHY_SETUP_CONTEXT:-runtime} == "provision-owner" ]]; then
  python3 "$OMARCHY_PATH/default/pi/user-defaults.py" "$OMARCHY_PATH" "$HOME"
fi
