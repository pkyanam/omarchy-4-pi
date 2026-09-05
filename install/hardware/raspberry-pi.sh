if omarchy-hw-raspberry-pi; then
  config_file="${OMARCHY_RPI_CONFIG_PATH:-}"
  modules_file="${OMARCHY_RPI_MODULES_PATH:-/etc/modules-load.d/omarchy-rpi.conf}"

  set_config_value() {
    local key="$1" value="$2" temporary
    if grep -Eq "^[[:space:]]*${key}=" "$config_file"; then
      temporary=$(mktemp)
      awk -v key="$key" -v value="$value" '
        $0 ~ "^[[:space:]]*" key "=" { print key "=" value; next }
        { print }
      ' "$config_file" >"$temporary"
      cp "$temporary" "$config_file"
      rm -f "$temporary"
    else
      echo "$key=$value" >>"$config_file"
    fi
  }

  if [[ -z $config_file ]]; then
    for candidate in /boot/config.txt /boot/firmware/config.txt; do
      if [[ -f $candidate ]]; then
        config_file="$candidate"
        break
      fi
    done
  fi

  if [[ -z $config_file ]]; then
    echo "Warning: Raspberry Pi boot config was not found; VC4 KMS was not configured." >&2
  else
    if ! grep -Eq '^[[:space:]]*dtoverlay=vc4-kms-v3d(-pi4)?([,[:space:]]|$)' "$config_file"; then
      cat >>"$config_file" <<'EOF'

[all]
# Omarchy: full KMS is required by the Hyprland Wayland session.
dtoverlay=vc4-kms-v3d
EOF
    fi

    set_config_value max_framebuffers 2
    set_config_value disable_fw_kms_setup 1

    # Keep both HDMI audio (provided by full KMS) and the Pi 4's onboard
    # analogue output available. Appending this exact setting also wins over
    # an earlier audio=off while remaining idempotent on repeat installs.
    if ! grep -Fxq 'dtparam=audio=on' "$config_file"; then
      echo 'dtparam=audio=on' >>"$config_file"
    fi
  fi

  install -d "$(dirname "$modules_file")"
  printf '%s\n' vc4 v3d raspberrypi_hwmon >"$modules_file"
  omarchy-pkg-add vulkan-broadcom
  omarchy-apply-pi-performance
fi
