# shellcheck shell=bash
if omarchy-hw-raspberry-pi; then
  omarchy_pi_configure_hardware() {
    local modules_file=${OMARCHY_RPI_MODULES_PATH:-/etc/modules-load.d/omarchy-rpi.conf}
    local -a firmware_args=()
    if [[ -n ${OMARCHY_RPI_CONFIG_PATH:-} ]]; then
      firmware_args=(--path "$OMARCHY_RPI_CONFIG_PATH")
    fi
    # Explicit failure handling also works when a sourcing caller tests this
    # leaf in an if/|| context, where Bash disables errexit inside it.
    python3 "$OMARCHY_PATH/default/pi/firmware-config.py" "${firmware_args[@]}" || return 1

    install -d "$(dirname "$modules_file")" || return 1
    printf '%s\n' vc4 v3d raspberrypi_hwmon >"$modules_file" || return 1
    omarchy-pkg-add vulkan-broadcom || return 1
    omarchy-apply-pi-performance
  }
  omarchy_pi_configure_hardware
fi
