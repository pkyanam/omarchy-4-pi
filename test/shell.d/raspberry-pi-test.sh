#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

case ${1:-} in
  ""|--rootfs-audit-only) ;;
  *) fail "usage: raspberry-pi-test.sh [--rootfs-audit-only]" ;;
esac

if [[ ${1:-} != "--rootfs-audit-only" ]]; then
  model="$test_tmp/model"
  printf 'Raspberry Pi 4 Model B Rev 1.5\0' >"$model"
  OMARCHY_RPI_MODEL_PATH="$model" "$ROOT/bin/omarchy-hw-raspberry-pi" || fail "Raspberry Pi device-tree detector accepts a Pi 4 model"
  pass "Raspberry Pi device-tree detector accepts a Pi 4 model"

  printf 'Apple Mac mini\0' >"$model"
  if OMARCHY_RPI_MODEL_PATH="$model" "$ROOT/bin/omarchy-hw-raspberry-pi"; then
    fail "Raspberry Pi device-tree detector rejects other ARM hardware"
  fi
  pass "Raspberry Pi device-tree detector rejects other ARM hardware"

  printf 'Raspberry Pi 4 Model B Rev 1.5\0' >"$model"
  boot_config="$test_tmp/config.txt"
  modules_file="$test_tmp/modules-load.d/omarchy-rpi.conf"
  cat >"$boot_config" <<'EOF'
arm_64bit=1
max_framebuffers=1
disable_fw_kms_setup=0
EOF

  fake_bin="$test_tmp/bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/omarchy-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
EOF
  chmod +x "$fake_bin/omarchy-pkg-add"
  cat >"$fake_bin/omarchy-apply-pi-performance" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$fake_bin/omarchy-apply-pi-performance"

  TEST_LOG="$test_tmp/calls.log" \
  PATH="$fake_bin:$ROOT/bin:$PATH" \
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_CONFIG_PATH="$boot_config" \
  OMARCHY_RPI_MODULES_PATH="$modules_file" \
    "$BASH" -euo pipefail "$ROOT/install/hardware/raspberry-pi.sh"

  grep -Fx 'dtoverlay=vc4-kms-v3d' "$boot_config" >/dev/null || fail "Pi hardware setup enables full VC4 KMS"
  grep -Fx 'max_framebuffers=2' "$boot_config" >/dev/null || fail "Pi hardware setup configures two KMS framebuffers"
  grep -Fx 'disable_fw_kms_setup=1' "$boot_config" >/dev/null || fail "Pi hardware setup delegates modesetting to KMS"
  grep -Fx 'dtparam=audio=on' "$boot_config" >/dev/null || fail "Pi hardware setup enables onboard audio"
  [[ $(grep -c '^dtoverlay=vc4-kms-v3d$' "$boot_config") == "1" ]] || fail "Pi hardware setup adds KMS exactly once"
  printf 'vc4\nv3d\nraspberrypi_hwmon\n' | cmp -s - "$modules_file" || fail "Pi hardware setup loads graphics and under-voltage sensor modules"
  grep -Fx 'vulkan-broadcom' "$test_tmp/calls.log" >/dev/null || fail "Pi hardware setup installs the Broadcom Vulkan driver"
  pass "Pi hardware setup configures the graphics stack"

  cat >"$fake_bin/vcgencmd" <<'EOF'
#!/bin/bash
[[ ${VCGENCMD_FAIL:-0} == 0 ]] || exit 1
printf '%s\n' "${VCGENCMD_OUTPUT:-throttled=0x50005}"
EOF
  cat >"$fake_bin/free" <<'EOF'
#!/bin/bash
printf 'Mem: 8Gi 2Gi 6Gi\n'
EOF
  cat >"$fake_bin/df" <<'EOF'
#!/bin/bash
printf 'Filesystem Size Used Avail Use%% Mounted\n/dev/root 30G 10G 20G 34%% /\n'
EOF
  chmod +x "$fake_bin/vcgencmd" "$fake_bin/free" "$fake_bin/df"
  hwmon_root="$test_tmp/hwmon"
  thermal_root="$test_tmp/thermal"
  mkdir -p "$hwmon_root/hwmon0" "$thermal_root/thermal_zone0"
  printf 'rpi_volt\n' >"$hwmon_root/hwmon0/name"
  printf '0\n' >"$hwmon_root/hwmon0/in0_lcrit_alarm"
  printf 'cpu-thermal\n' >"$thermal_root/thermal_zone0/type"
  printf '47200\n' >"$thermal_root/thermal_zone0/temp"
  OMARCHY_RPI_MODEL_PATH="$model" PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-status" >"$test_tmp/pi-status"
  grep -F 'ACTIVE: under-voltage, throttled; previously: under-voltage, throttled (0x50005)' \
    "$test_tmp/pi-status" >/dev/null || fail "Pi status decodes active and historical power flags"
  VCGENCMD_OUTPUT=throttled=0x0 OMARCHY_RPI_MODEL_PATH="$model" PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-status" >"$test_tmp/pi-status-ok"
  grep -F 'OK — no under-voltage or throttling flags (0x0)' "$test_tmp/pi-status-ok" >/dev/null ||
    fail "Pi status makes a healthy power state obvious"
  VCGENCMD_OUTPUT=unavailable OMARCHY_RPI_MODEL_PATH="$model" PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-status" >"$test_tmp/pi-status-unknown"
  grep -F 'unknown (unavailable)' "$test_tmp/pi-status-unknown" >/dev/null ||
    fail "Pi status explains an unreadable firmware response"
  VCGENCMD_FAIL=1 \
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-status" >"$test_tmp/pi-status-kernel"
  grep -F 'Temperature: 47.2°C' "$test_tmp/pi-status-kernel" >/dev/null || fail "Pi status reads the kernel CPU temperature"
  grep -F 'Power:       OK — kernel under-voltage alarm clear' "$test_tmp/pi-status-kernel" >/dev/null || fail "Pi status falls back to the kernel under-voltage sensor"
  pass "Pi status explains Raspberry Pi power flags"

  cat >"$fake_bin/uname" <<'EOF'
#!/bin/bash
[[ ${PI_CHECK_FAIL:-0} == 0 ]] && echo aarch64 || echo x86_64
EOF
  cat >"$fake_bin/systemctl" <<'EOF'
#!/bin/bash
if [[ $1 == is-active ]]; then
  [[ ${PI_CHECK_FAIL:-0} == 0 ]]
elif [[ $1 == --failed ]]; then
  [[ ${PI_CHECK_SYSTEMCTL_FAIL:-0} == 0 ]] || exit 1
  [[ ${PI_CHECK_FAIL:-0} == 0 ]] ||
    echo 'failed-example.service loaded failed failed Example failure'
fi
EOF
  cat >"$fake_bin/pgrep" <<'EOF'
#!/bin/bash
[[ ${PI_CHECK_FAIL:-0} == 0 ]]
EOF
  cat >"$fake_bin/nmcli" <<'EOF'
#!/bin/bash
[[ ${PI_CHECK_FAIL:-0} == 0 ]] && echo connected || echo disconnected
EOF
  cat >"$fake_bin/wpctl" <<'EOF'
#!/bin/bash
[[ ${PI_CHECK_FAIL:-0} == 0 ]] && echo 'Volume: 0.50' || exit 1
EOF
  cat >"$fake_bin/hyprctl" <<'EOF'
#!/bin/bash
[[ -n ${HYPRCTL_LOG:-} ]] && printf '%s\n' "$*" >>"$HYPRCTL_LOG"
action=${!#}
if [[ $action == instances ]]; then
  if [[ -n ${PI_CHECK_INSTANCES_JSON:-} ]]; then
    printf '%s\n' "$PI_CHECK_INSTANCES_JSON"
  else
    printf '[{"instance":"test","pid":%d}]\n' "${PI_CHECK_LIVE_PID:-$PPID}"
  fi
elif [[ $action == monitors ]]; then
  [[ ${PI_CHECK_DISPLAY_FAIL:-0} == 0 ]] && printf '[{"name":"HDMI-A-1","width":1920,"height":1080,"disabled":false}]\n' || printf '[]\n'
elif [[ $action == devices ]]; then
  [[ ${PI_CHECK_INPUT_MISSING:-0} == 0 ]] && printf '{"keyboards":[{"name":"test-keyboard"}],"mice":[],"touch":[],"tablets":[]}\n' || printf '{"keyboards":[],"mice":[],"touch":[],"tablets":[]}\n'
else
  exit 1
fi
EOF
  cat >"$fake_bin/bluetoothctl" <<'EOF'
#!/bin/bash
echo 'Controller 00:00:00:00:00:00 test'
[[ ${PI_CHECK_FAIL:-0} == 0 ]] && echo 'Powered: yes' || echo 'Powered: no'
EOF
  chmod +x "$fake_bin/uname" "$fake_bin/systemctl" "$fake_bin/pgrep" \
    "$fake_bin/nmcli" "$fake_bin/wpctl" "$fake_bin/hyprctl" "$fake_bin/bluetoothctl"

  check_module_root="$test_tmp/modules"
  check_dri_root="$test_tmp/dri"
  check_provisioning_root="$test_tmp/provisioning"
  mkdir -p "$check_module_root/v3d" "$check_dri_root" "$check_provisioning_root"
  touch "$check_dri_root/renderD128"
  check_drm_root="$test_tmp/drm"
  check_alsa_root="$test_tmp/asound"
  hyprctl_log="$test_tmp/hyprctl.log"
  mkdir -p "$check_drm_root/card1-HDMI-A-1" "$check_alsa_root/card2" "$check_alsa_root/card3"
  cat >"$check_alsa_root/cards" <<'EOF'
 2 [vc4hdmi0       ]: vc4-hdmi - vc4-hdmi-0
 3 [vc4hdmi1       ]: vc4-hdmi - vc4-hdmi-1
EOF
  printf 'connected\n' >"$check_drm_root/card1-HDMI-A-1/status"
  printf 'fixture-edid\n' >"$check_drm_root/card1-HDMI-A-1/edid"
  cat >"$check_alsa_root/card2/eld#0" <<'EOF'
monitor_present         1
eld_valid               1
sad_count               1
EOF
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  HYPRCTL_LOG="$hyprctl_log" \
  PI_CHECK_LIVE_PID=$$ \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-ok" ||
    fail "Pi acceptance command succeeds for a healthy hardware fixture"
  grep -Fx 'PASS  V3D graphics — kernel module loaded; renderD128 present' \
    "$test_tmp/pi-check-ok" >/dev/null || fail "Pi acceptance command verifies the V3D render node"
  grep -Fx 'PASS  Audio — default PipeWire sink ready (Volume: 0.50)' \
    "$test_tmp/pi-check-ok" >/dev/null || fail "Pi acceptance command verifies the default audio sink"
  grep -Fx 'PASS  Display link — card1-HDMI-A-1 connected; EDID ready on card1-HDMI-A-1' \
    "$test_tmp/pi-check-ok" >/dev/null || fail "Pi acceptance command verifies connected output and EDID"
  grep -Fx 'PASS  Desktop output — Hyprland reports an active monitor' \
    "$test_tmp/pi-check-ok" >/dev/null || fail "Pi acceptance command verifies compositor output"
  grep -Fx 'PASS  Desktop input — Hyprland reports an input device' \
    "$test_tmp/pi-check-ok" >/dev/null || fail "Pi acceptance command verifies compositor input"
  grep -Fx -- '-i 0 -j monitors' "$hyprctl_log" >/dev/null ||
    fail "Pi acceptance command targets the sole live Hyprland instance"
  grep -Fx -- '-i 0 -j devices' "$hyprctl_log" >/dev/null ||
    fail "Pi acceptance command queries input in the sole live Hyprland instance"
  grep -Fx 'PASS  HDMI audio — kernel ELD reports audio descriptors' \
    "$test_tmp/pi-check-ok" >/dev/null || fail "Pi acceptance command verifies the HDMI audio handshake"
  grep -Fx 'Result: 0 failure(s), 0 warning(s)' "$test_tmp/pi-check-ok" >/dev/null ||
    fail "Pi acceptance command summarizes a healthy system"

  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  VCGENCMD_FAIL=1 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-kernel-sensors"
  grep -Fx 'PASS  Power/thermals — under-voltage alarm clear; CPU 47.2°C' \
    "$test_tmp/pi-check-kernel-sensors" >/dev/null ||
    fail "Pi acceptance command falls back to kernel-native voltage and temperature sensors"

  : >"$check_drm_root/card1-HDMI-A-1/edid"
  : >"$check_alsa_root/card2/eld#0"
  PI_CHECK_INPUT_MISSING=1 \
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-degraded" ||
    fail "Pi acceptance command keeps recoverable peripheral gaps as warnings"
  grep -Fx 'WARN  Display link — card1-HDMI-A-1 connected without EDID; native modes and HDMI audio are not proven' \
    "$test_tmp/pi-check-degraded" >/dev/null || fail "Pi acceptance command detects a missing EDID"
  grep -Fx 'WARN  HDMI audio — no valid ELD audio descriptors; a default sink does not prove monitor audio' \
    "$test_tmp/pi-check-degraded" >/dev/null || fail "Pi acceptance command distinguishes PipeWire from HDMI readiness"
  grep -Fx 'WARN  Desktop input — Hyprland reports no keyboard, pointer, touch, or tablet device' \
    "$test_tmp/pi-check-degraded" >/dev/null || fail "Pi acceptance command reports missing desktop input"
  pass "Pi acceptance command detects appliance-facing display, audio, and input regressions"

  printf 'disconnected\n' >"$check_drm_root/card1-HDMI-A-1/status"
  if OMARCHY_RPI_MODEL_PATH="$model" \
    OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
    OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
    OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
    OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
    OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
    OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
    OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
    VCGENCMD_OUTPUT=throttled=0x0 \
    PATH="$fake_bin:$PATH" \
      "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-disconnected"; then
    fail "Pi acceptance command rejects a disconnected physical display"
  fi
  grep -Fx 'FAIL  Display link — no connected DRM output' "$test_tmp/pi-check-disconnected" >/dev/null ||
    fail "Pi acceptance command reports a disconnected physical display"
  printf 'connected\n' >"$check_drm_root/card1-HDMI-A-1/status"
  pass "Pi acceptance command rejects a disconnected physical display"

  printf 'unknown\n' >"$check_drm_root/card1-HDMI-A-1/status"
  printf 'fixture-edid\n' >"$check_drm_root/card1-HDMI-A-1/edid"
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-unknown-status" ||
    fail "Pi acceptance command does not reject an output with unknown status and readable EDID"
  grep -Fx 'WARN  Display link — card1-HDMI-A-1 reports unknown status with readable EDID; compositor state determines usability' \
    "$test_tmp/pi-check-unknown-status" >/dev/null ||
    fail "Pi acceptance command distinguishes unknown connector status from disconnection"
  printf 'connected\n' >"$check_drm_root/card1-HDMI-A-1/status"
  pass "Pi acceptance command preserves uncertain but usable DRM outputs"

  stale_pid=999999
  : >"$hyprctl_log"
  PI_CHECK_LIVE_PID=$$ \
  PI_CHECK_INSTANCES_JSON="[{\"instance\":\"stale\",\"pid\":$stale_pid},{\"instance\":\"live\",\"pid\":$$}]" \
  HYPRCTL_LOG="$hyprctl_log" \
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-stale-instance" ||
    fail "Pi acceptance command selects the sole live Hyprland instance"
  grep -Fx -- '-i 1 -j monitors' "$hyprctl_log" >/dev/null ||
    fail "Pi acceptance command ignores a stale Hyprland instance"
  pass "Pi acceptance command selects the sole live Hyprland instance"

  # sysfs attributes commonly report a zero stat size even when reading them
  # returns data. A FIFO reproduces that behavior for the EDID byte check.
  mv "$check_drm_root/card1-HDMI-A-1/edid" "$check_drm_root/card1-HDMI-A-1/edid-empty"
  edid_fifo="$check_drm_root/card1-HDMI-A-1/edid"
  mkfifo "$edid_fifo"
  (
    printf 'fixture-edid\n' >"$edid_fifo"
  ) &
  edid_writer=$!
  cat >"$check_alsa_root/card2/eld#0" <<'EOF'
monitor_present         1
eld_valid               1
sad_count               1
EOF
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-sysfs-edid" ||
    fail "Pi acceptance command reads data from a zero-stat-size EDID attribute"
  wait "$edid_writer" || fail "EDID FIFO writer completed successfully"
  grep -Fx 'PASS  Display link — card1-HDMI-A-1 connected; EDID ready on card1-HDMI-A-1' \
    "$test_tmp/pi-check-sysfs-edid" >/dev/null || fail "Pi acceptance command reads EDID bytes instead of trusting stat size"
  mv "$check_drm_root/card1-HDMI-A-1/edid" "$check_drm_root/card1-HDMI-A-1/edid-fifo"
  mv "$check_drm_root/card1-HDMI-A-1/edid-empty" "$check_drm_root/card1-HDMI-A-1/edid"
  pass "Pi acceptance command handles sysfs EDID attributes with zero reported size"

  cat >"$check_alsa_root/card2/eld#0" <<'EOF'
monitor_name            fixture-monitor
sad_count               1
EOF
  printf 'fixture-edid\n' >"$check_drm_root/card1-HDMI-A-1/edid"
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-vc4-eld" ||
    fail "Pi acceptance command accepts VC4 ELD descriptors"
  grep -Fx 'PASS  HDMI audio — kernel ELD reports audio descriptors' \
    "$test_tmp/pi-check-vc4-eld" >/dev/null || fail "Pi acceptance command accepts VC4 ELD without optional PC fields"
  pass "Pi acceptance command accepts the Raspberry Pi VC4 ELD shape"

  mkdir -p "$check_drm_root/card1-HDMI-A-2"
  printf 'disconnected\n' >"$check_drm_root/card1-HDMI-A-1/status"
  printf 'connected\n' >"$check_drm_root/card1-HDMI-A-2/status"
  printf 'fixture-edid\n' >"$check_drm_root/card1-HDMI-A-2/edid"
  : >"$check_alsa_root/card3/eld#0"
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-wrong-eld" ||
    fail "Pi acceptance command keeps a missing matching HDMI ELD as a warning"
  grep -Fx 'WARN  HDMI audio — no valid ELD audio descriptors; a default sink does not prove monitor audio' \
    "$test_tmp/pi-check-wrong-eld" >/dev/null ||
    fail "Pi acceptance command ignores ELD descriptors from a different HDMI port"
  cat >"$check_alsa_root/card3/eld#0" <<'EOF'
monitor_name            fixture-monitor-two
sad_count               2
EOF
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
  OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
  OMARCHY_RPI_DRM_ROOT="$check_drm_root" \
  OMARCHY_RPI_ALSA_ROOT="$check_alsa_root" \
  OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
  OMARCHY_RPI_HWMON_ROOT="$hwmon_root" \
  OMARCHY_RPI_THERMAL_ROOT="$thermal_root" \
  VCGENCMD_OUTPUT=throttled=0x0 \
  PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-matching-eld" ||
    fail "Pi acceptance command accepts the matching HDMI port's ELD"
  grep -Fx 'PASS  HDMI audio — kernel ELD reports audio descriptors' \
    "$test_tmp/pi-check-matching-eld" >/dev/null ||
    fail "Pi acceptance command accepts ELD descriptors from the connected HDMI port"
  printf 'connected\n' >"$check_drm_root/card1-HDMI-A-1/status"
  printf 'disconnected\n' >"$check_drm_root/card1-HDMI-A-2/status"
  pass "Pi acceptance command correlates HDMI audio evidence to the connected port"

  touch "$check_provisioning_root/grow-root-pending" "$check_provisioning_root/pending"
  if PI_CHECK_FAIL=1 \
    OMARCHY_RPI_MODEL_PATH="$model" \
    OMARCHY_RPI_MODULE_ROOT="$test_tmp/missing-modules" \
    OMARCHY_RPI_DRI_ROOT="$test_tmp/missing-dri" \
    OMARCHY_RPI_PROVISIONING_ROOT="$check_provisioning_root" \
    VCGENCMD_OUTPUT=throttled=0x1 \
    PATH="$fake_bin:$PATH" \
      "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-failed"; then
    fail "Pi acceptance command rejects an unhealthy hardware fixture"
  fi
  grep -Fx 'FAIL  Root expansion — still pending' "$test_tmp/pi-check-failed" >/dev/null ||
    fail "Pi acceptance command reports incomplete storage growth"
  grep -Fx 'FAIL  Power/thermals — active firmware warning (0x1)' \
    "$test_tmp/pi-check-failed" >/dev/null || fail "Pi acceptance command reports active undervoltage"
  grep -F 'failed-example.service' "$test_tmp/pi-check-failed" >/dev/null ||
    fail "Pi acceptance command names failed system units"

  if PI_CHECK_SYSTEMCTL_FAIL=1 \
    OMARCHY_RPI_MODEL_PATH="$model" \
    OMARCHY_RPI_MODULE_ROOT="$check_module_root" \
    OMARCHY_RPI_DRI_ROOT="$check_dri_root" \
    OMARCHY_RPI_PROVISIONING_ROOT="$test_tmp/complete-provisioning" \
    VCGENCMD_OUTPUT=throttled=0x0 \
    PATH="$fake_bin:$PATH" \
      "$ROOT/bin/omarchy-pi-check" >"$test_tmp/pi-check-systemctl-failed"; then
    fail "Pi acceptance command rejects an unreadable failed-unit state"
  fi
  grep -Fx 'FAIL  System services — failed-unit query failed' \
    "$test_tmp/pi-check-systemctl-failed" >/dev/null ||
    fail "Pi acceptance command fails closed when systemd cannot report health"
  pass "Pi acceptance command grades the real-hardware checklist"

  TEST_LOG="$test_tmp/calls.log" \
  PATH="$fake_bin:$ROOT/bin:$PATH" \
  OMARCHY_RPI_MODEL_PATH="$model" \
  OMARCHY_RPI_CONFIG_PATH="$boot_config" \
  OMARCHY_RPI_MODULES_PATH="$modules_file" \
    "$BASH" -euo pipefail "$ROOT/install/hardware/raspberry-pi.sh"
  [[ $(grep -c '^dtoverlay=vc4-kms-v3d$' "$boot_config") == "1" ]] || fail "Pi hardware setup is idempotent"
  [[ $(grep -c '^dtparam=audio=on$' "$boot_config") == "1" ]] || fail "Pi audio setup is idempotent"
  pass "Pi hardware setup is idempotent"

  "$BASH" -euo pipefail "$ROOT/install/hardware/apple/fix-spi-keyboard.sh"
  pass "DMI-only hardware probes are harmless on device-tree systems"

  OMARCHY_ROOT_FSTYPE=ext4 \
  OMARCHY_SNAPPER_CONFIG_PATH="$test_tmp/snapper/root" \
  OMARCHY_SNAPPER_CONF_PATH="$test_tmp/conf.d/snapper" \
    "$BASH" -euo pipefail "$ROOT/install/config/snapper.sh" >"$test_tmp/snapper-output"
  [[ ! -e $test_tmp/snapper/root ]] || fail "ext4 setup does not create an unusable Snapper configuration"
  grep -F 'root filesystem is not Btrfs' "$test_tmp/snapper-output" >/dev/null || fail "ext4 setup explains why Snapper is skipped"
  pass "ext4 installs skip Btrfs-only Snapper setup"

  "$BASH" -n "$ROOT/install-rpi4.sh"
  "$BASH" -n "$ROOT/build-packages-rpi4.sh"
  "$BASH" -n "$ROOT/bin/omarchy-update-rpi4"
  "$BASH" -n "$ROOT/bin/omarchy-rpi4-grow-root"
  "$BASH" -n "$ROOT/bin/omarchy-pi-status"
  "$BASH" -n "$ROOT/bin/omarchy-pi-check"
  "$BASH" -n "$ROOT/image/build-rpi4-image.sh"
  "$BASH" -n "$ROOT/image/build-rpi4-image-macos.sh"
  "$BASH" -n "$ROOT/image/audit-rpi4-rootfs.sh"
  "$BASH" -n "$ROOT/image/generate-imager-catalog.sh"
  "$BASH" -n "$ROOT/image/validate-imager-catalog.sh"
  "$BASH" -n "$ROOT/image/generate-local-imager-manifest.sh"
  "$BASH" -n "$ROOT/image/open-in-rpi-imager-macos.sh"
  "$BASH" -n "$ROOT/image/prepare-release-assets.sh"
  pass "Raspberry Pi install, image, and update entrypoints parse"

  macos_build_help=$("$BASH" "$ROOT/image/build-rpi4-image-macos.sh" --help)
  grep -F 'OMARCHY_LOCAL_CPUS' <<<"$macos_build_help" >/dev/null ||
    fail "macOS builder documents its balanced core override"
  grep -F 'OMARCHY_XZ_PRESET' <<<"$macos_build_help" >/dev/null ||
    fail "macOS builder documents its fast compression override"
  pass "macOS image builder help is instant and self-contained"

  limine_test="$test_tmp/limine-refresh"
  mkdir -p "$limine_test/bin"
  printf 'OMARCHY_PACMAN_PROFILE=rpi4\n' >"$limine_test/profile"
  cat >"$limine_test/bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$LIMINE_TEST_CALLS"
exit 1
SH
  chmod +x "$limine_test/bin/sudo"
  limine_output=$(LIMINE_TEST_CALLS="$limine_test/calls" \
    OMARCHY_RPI4_PROFILE="$limine_test/profile" \
    PATH="$limine_test/bin:$PATH" \
    "$BASH" "$ROOT/bin/omarchy-refresh-limine") ||
    fail "Pi config refresh skips the PC bootloader without failing"
  [[ ! -e $limine_test/calls ]] || fail "Pi config refresh never invokes Limine through sudo"
  grep -F 'Raspberry Pi firmware boot does not use Limine' <<<"$limine_output" >/dev/null ||
    fail "Pi config refresh explains why Limine is skipped"
  pass "Pi config refresh leaves the firmware boot partition alone"

  (
    root_mount="$test_tmp/cache-image"
    work_dir="$test_tmp/cache-work"
    mkdir -p "$root_mount/etc" "$root_mount/var/cache/pacman/pkg"
    printf 'cached package\n' >"$root_mount/var/cache/pacman/pkg/base.pkg.tar.zst"
    mount() { printf '%s\n' "$*" >>"$test_tmp/cache-mounts"; }
    eval "$(sed -n '/^mount_chroot_filesystems()/,/^}/p' "$ROOT/image/build-rpi4-image.sh")"
    mount_chroot_filesystems
    [[ -f $work_dir/package-work/pacman/base.pkg.tar.zst ]] || fail "factory preserves base package cache outside image"
    [[ ! -e $root_mount/var/cache/pacman/pkg/base.pkg.tar.zst ]] || fail "base cache does not occupy the hidden image directory"
    grep -Fx -- "--bind $work_dir/package-work/pacman $root_mount/var/cache/pacman/pkg" "$test_tmp/cache-mounts" >/dev/null ||
      fail "factory binds pacman downloads to external build storage"
  )
  pass "factory package downloads use external build storage"

  # Verified offline Node preloading, user-pin preservation, and failed setup
  # retries are covered behaviorally in rpi45-mise-offline-test.sh.

  catalog_source="$test_tmp/catalog.img"
  catalog_archive="$catalog_source.xz"
  catalog_json="$test_tmp/os-list.json"
  dd if=/dev/zero of="$catalog_source" bs=4096 count=1 2>/dev/null
  xz --stdout "$catalog_source" >"$catalog_archive"
  "$BASH" "$ROOT/image/generate-imager-catalog.sh" "$catalog_archive" \
    https://example.invalid/omarchy-4-pi.img.xz "$catalog_json"
  "$BASH" "$ROOT/image/validate-imager-catalog.sh" "$catalog_json" >/dev/null ||
    fail "device-first catalog validator accepts a selectable Pi 4 image"
  python3 - "$catalog_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    catalog = json.load(stream)

device = catalog["imager"]["devices"][0]
assert device["name"] == "Raspberry Pi 4"
assert device["tags"] == ["pi4-64bit", "pi4-32bit"]
assert device["matching_type"] == "inclusive"
assert device["architecture"] == "armv8"
entry = catalog["os_list"][0]
assert entry["devices"] == ["pi4-64bit"]
assert set(device["tags"]) & set(entry["devices"])
assert entry["architecture"] == "armv8"
assert entry["init_format"] == "rpi-preseed"
assert entry["extract_size"] == 4096
assert len(entry["extract_sha256"]) == 64
assert len(entry["image_download_sha256"]) == 64
PY
  pass "Raspberry Pi Imager catalog exposes a selectable Pi 4 and records image integrity"

  catalog_without_devices="$test_tmp/os-list-without-devices.json"
  python3 - "$catalog_json" "$catalog_without_devices" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    catalog = json.load(stream)
catalog.pop("imager")
with open(sys.argv[2], "w", encoding="utf-8") as stream:
    json.dump(catalog, stream)
PY
  if "$BASH" "$ROOT/image/validate-imager-catalog.sh" "$catalog_without_devices" >/dev/null 2>&1; then
    fail "device-first catalog validator rejects a catalog with a blank device chooser"
  fi

  catalog_with_hidden_os="$test_tmp/os-list-hidden-os.json"
  python3 - "$catalog_json" "$catalog_with_hidden_os" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    catalog = json.load(stream)
catalog["os_list"][0]["devices"] = ["pi5-64bit"]
with open(sys.argv[2], "w", encoding="utf-8") as stream:
    json.dump(catalog, stream)
PY
  if "$BASH" "$ROOT/image/validate-imager-catalog.sh" "$catalog_with_hidden_os" >/dev/null 2>&1; then
    fail "device-first catalog validator rejects an OS hidden by mismatched device tags"
  fi
  pass "catalog publication fails closed before a blank Imager device screen can ship"

  local_catalog_dir="$test_tmp/local catalog"
  local_catalog_archive="$local_catalog_dir/Omarchy 4 Pi.img.xz"
  local_catalog_manifest="$local_catalog_dir/Omarchy 4 Pi.imager.json"
  mkdir -p "$local_catalog_dir"
  cp "$catalog_archive" "$local_catalog_archive"
  "$BASH" "$ROOT/image/generate-local-imager-manifest.sh" \
    "$local_catalog_archive" "$local_catalog_manifest" >/dev/null
  python3 - "$local_catalog_manifest" "$local_catalog_archive" <<'PY'
import json
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

with open(sys.argv[1], encoding="utf-8") as stream:
    entry = json.load(stream)["os_list"][0]

url = urlparse(entry["url"])
assert url.scheme == "file"
assert Path(unquote(url.path)).resolve() == Path(sys.argv[2]).resolve()
assert "%20" in entry["url"]
assert entry["init_format"] == "rpi-preseed"
assert entry["image_download_size"] == Path(sys.argv[2]).stat().st_size
PY
  pass "local Imager manifests preserve customization and path-safe image URLs"
fi

# Build the same fixture with its real owner on either host. An unprivileged
# run must be refused specifically for ownership; root CI runs all corruption
# cases after establishing a completely passing baseline.
umask 022

audit_root="$test_tmp/audit-root"
audit_boot="$test_tmp/audit-boot"
mkdir -p \
  "$audit_boot/dtbs/broadcom" \
  "$audit_root/etc/modules-load.d" \
  "$audit_root/etc/pacman.d" \
  "$audit_root/etc/ssh" \
  "$audit_root/etc/systemd/system/bluetooth.target.wants" \
  "$audit_root/etc/systemd/system/multi-user.target.wants" \
  "$audit_root/etc/systemd/system/omarchy-provision-owner.service.d" \
  "$audit_root/etc/systemd/system/omarchy-provision-hardware.service.d" \
  "$audit_root/etc/systemd/system/avahi-daemon.service.d" \
  "$audit_root/etc/systemd/system/sddm.service.d" \
  "$audit_root/etc/systemd/user/pipewire.service.wants" \
  "$audit_root/etc/systemd/user/sockets.target.wants" \
  "$audit_root/etc/skel/.config/hypr" \
  "$audit_root/usr/bin" \
  "$audit_root/usr/lib/omarchy-hyprland-titlebars" \
  "$audit_root/usr/local/share/wayland-sessions" \
  "$audit_root/usr/share/omarchy/shell" \
  "$audit_root/usr/share/omarchy/default/hypr" \
  "$audit_root/usr/share/omarchy-rpi4" \
  "$audit_root/usr/share/pacman/keyrings" \
  "$audit_root/usr/share/sddm/themes/omarchy" \
  "$audit_root/opt" \
  "$audit_root/var/lib/omarchy/provisioning/packages" \
  "$audit_root/var/lib/omarchy/image" \
  "$audit_root/var/lib/pacman/local"

for asset in kernel8.img Image initramfs-linux.img bcm2711-rpi-4-b.dtb dtbs/broadcom/bcm2711-rpi-4-b.dtb boot.scr boot.txt start4.elf fixup4.dat; do
  printf 'fixture boot asset\n' >"$audit_boot/$asset"
done
touch \
  "$audit_root/var/lib/omarchy/provisioning/pending" \
  "$audit_root/var/lib/omarchy/provisioning/grow-root-pending" \
  "$audit_root/var/lib/omarchy/image/pacman-keyring" \
  "$audit_root/usr/share/omarchy/shell/shell.qml" \
  "$audit_root/usr/share/omarchy-rpi4/hyprland-config-verified" \
  "$audit_root/etc/skel/.config/hypr/hyprland.lua" \
  "$audit_root/usr/share/omarchy/default/hypr/raspberry-pi.lua" \
  "$audit_root/usr/share/sddm/themes/omarchy/Main.qml" \
  "$audit_root/usr/share/pacman/keyrings/archlinuxarm.gpg" \
  "$audit_root/usr/share/pacman/keyrings/omarchy.gpg"
printf 'format=1\nplatform=aarch64\n' >"$audit_root/var/lib/omarchy/image/target"
printf 'install/hardware/raspberry-pi.sh\n' >"$audit_root/var/lib/omarchy/image/deferred-steps"

printf 'arm_64bit=1\n' >"$audit_boot/config.txt"
python3 "$ROOT/default/pi/firmware-config.py" --path "$audit_boot/config.txt" >"$test_tmp/firmware-policy.log"
cat >"$audit_root/etc/fstab" <<'FSTAB'
LABEL=omarchyroot /     ext4 defaults,noatime 0 1
LABEL=OMARCHYBOOT /boot vfat defaults,noatime 0 2
FSTAB
printf 'vc4\nv3d\nraspberrypi_hwmon\n' >"$audit_root/etc/modules-load.d/omarchy-rpi.conf"
cp "$ROOT/default/pacman/pacman-rpi4.conf" "$audit_root/etc/pacman.conf"
cp "$ROOT/default/pacman/mirrorlist-rpi4" "$audit_root/etc/pacman.d/mirrorlist"
printf 'OMARCHY_PACMAN_PROFILE=rpi4\nOMARCHY_RPI4_PACKAGE_POLICY=stable-4.5\n' >"$audit_root/etc/omarchy-rpi4.conf"
printf 'root:x:0:0:root:/root:/bin/bash\nnobody:x:65534:65534:nobody:/:/usr/bin/nologin\n' >"$audit_root/etc/passwd"
printf 'root:!$y$locked:0:0:99999:7:::\n' >"$audit_root/etc/shadow"
: >"$audit_root/etc/machine-id"
cat >"$audit_root/usr/local/share/wayland-sessions/omarchy.desktop" <<'SESSION'
[Desktop Entry]
Name=Omarchy
Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop
SESSION
for unit in omarchy-rpi4-grow-root omarchy-provision-hardware omarchy-provision-owner omarchy-pi-cpu-policy; do
  ln -s "/etc/systemd/system/$unit.service" "$audit_root/etc/systemd/system/multi-user.target.wants/$unit.service"
done
ln -s /usr/lib/systemd/system/sddm.service "$audit_root/etc/systemd/system/display-manager.service"
for unit in NetworkManager avahi-daemon; do
  ln -s "/usr/lib/systemd/system/$unit.service" "$audit_root/etc/systemd/system/multi-user.target.wants/$unit.service"
done
ln -s /dev/null "$audit_root/etc/systemd/system/NetworkManager-wait-online.service"
ln -s /usr/lib/systemd/system/bluetooth.service "$audit_root/etc/systemd/system/bluetooth.target.wants/bluetooth.service"
for unit in pipewire pipewire-pulse; do
  ln -s "/usr/lib/systemd/user/$unit.socket" "$audit_root/etc/systemd/user/sockets.target.wants/$unit.socket"
done
ln -s /usr/lib/systemd/user/wireplumber.service "$audit_root/etc/systemd/user/pipewire.service.wants/wireplumber.service"
cp "$ROOT/install/provisioning/omarchy-provision-owner-rpi4.conf" "$audit_root/etc/systemd/system/omarchy-provision-owner.service.d/10-rpi4-grow-root.conf"
cp "$ROOT/install/provisioning/omarchy-provision-owner-rpi4-image.conf" "$audit_root/etc/systemd/system/omarchy-provision-owner.service.d/20-rpi4-image-hardware.conf"
cp "$ROOT/install/provisioning/omarchy-provision-hardware-rpi4.conf" "$audit_root/etc/systemd/system/omarchy-provision-hardware.service.d/10-rpi4-grow-root.conf"
cp "$ROOT/install/provisioning/omarchy-sddm-rpi4.conf" "$audit_root/etc/systemd/system/sddm.service.d/10-rpi4-owner-setup.conf"
cp "$ROOT/install/provisioning/omarchy-avahi-rpi4.conf" "$audit_root/etc/systemd/system/avahi-daemon.service.d/10-rpi4-owner-hostname.conf"

# Synthetic headers test the audit's ELF architecture check; no fixture binary
# is executed. Actual ARM loading and Hyprland parsing remain image-build gates.
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\267\000' >"$audit_root/usr/bin/Hyprland"
for executable in quickshell foot vcgencmd ttfx; do
  cp "$audit_root/usr/bin/Hyprland" "$audit_root/usr/bin/$executable"
done
cp "$audit_root/usr/bin/Hyprland" "$audit_root/usr/lib/omarchy-hyprland-titlebars/titlebars.so"
for executable in omarchy-shell omarchy-pi-check omarchy-pi-display omarchy-pi-report omarchy-pi-run omarchy-pi-tune omarchy-pi-benchmark omarchy-pi-cpu-policy omarchy-apply-pi-performance omarchy-update-rpi4-guard omarchy-rpi4-grow-root omarchy-rpi4-imager-preseed omarchy-provision-owner omarchy-provision-hardware; do
  cp "$ROOT/bin/$executable" "$audit_root/usr/bin/$executable"
done
chmod +x "$audit_root/usr/bin/"*
mkdir -p "$audit_root/usr/share/omarchy/default/pi" "$audit_root/etc/makepkg.conf.d" "$audit_root/etc/systemd/journald.conf.d"
cp "$ROOT/default/pi/tune.py" "$ROOT/default/pi/benchmark.py" "$ROOT/default/pi/build-budget.sh" "$ROOT/default/pi/firmware-config.py" "$audit_root/usr/share/omarchy/default/pi/"
cp "$ROOT/install/provisioning/omarchy-pi-tune-guard.service" "$ROOT/install/provisioning/omarchy-pi-cpu-policy.service" "$audit_root/etc/systemd/system/"
cp "$ROOT/default/pi/makepkg.conf" "$audit_root/etc/makepkg.conf.d/50-omarchy-pi.conf"
cp "$ROOT/default/pi/journald.conf" "$audit_root/etc/systemd/journald.conf.d/50-omarchy-pi.conf"
mkdir -p "$audit_root/etc/systemd/zram-generator.conf.d" "$audit_root/etc/systemd/user/app.slice.d" "$audit_root/etc/systemd/oomd.conf.d" "$audit_root/etc/sysctl.d"
cp "$ROOT/default/pi/zram.conf" "$audit_root/etc/systemd/zram-generator.conf.d/50-omarchy-pi.conf"
cp "$ROOT/default/pi/sysctl.conf" "$audit_root/etc/sysctl.d/99-omarchy-pi-writeback.conf"
cp "$ROOT/default/systemd/user/app.slice.d/10-oomd.conf" "$audit_root/etc/systemd/user/app.slice.d/50-omarchy-pi.conf"
cp "$ROOT/default/pi/oomd.conf" "$audit_root/etc/systemd/oomd.conf.d/50-omarchy-pi.conf"

mkdir -p "$audit_root/usr/lib/firmware/updates/brcm" "$audit_root/usr/share/licenses/broadcom/cypress"
for firmware in brcmfmac43455-sdio.raspberrypi,4-model-b.bin brcmfmac43455-sdio.raspberrypi,4-model-b.txt brcmfmac43455-sdio.raspberrypi,4-model-b.clm_blob BCM4345C0.hcd; do
  printf 'firmware fixture\n' >"$audit_root/usr/lib/firmware/updates/brcm/$firmware"
done
printf 'license fixture\n' >"$audit_root/usr/share/licenses/broadcom/cypress/LICENSE"

audit_packages=(
  hyprland quickshell mesa vulkan-broadcom linux-aarch64 raspberrypi-utils firmware-raspberrypi
  sddm networkmanager wpa_supplicant iw wireless-regdb avahi nss-mdns openssh ufw bluez bluez-tools bluez-utils
  alsa-utils pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber
  uwsm chromium foot ttfx omarchy omarchy-settings linux-firmware-broadcom omarchy-keyring archlinuxarm-keyring
  omasnap owe omarchy-hyprland-titlebars omarchy-speedtest omarchy-power-profiles-daemon
  monologue hype disktree-bin gliff signed mise-bin rtkit zram-generator cloud-guest-utils python
  fcitx5 fcitx5-chewing fcitx5-chinese-addons fcitx5-gtk fcitx5-hangul fcitx5-mozc fcitx5-qt fcitx5-table-extra
)
for package in "${audit_packages[@]}"; do
  case $package in
    omarchy|omarchy-settings) version=4.5.0.pi4.1-1 ;;
    hyprland) version=0.56.2-7 ;;
    omarchy-hyprland-titlebars) version=0.2.2-2 ;;
    quickshell) version=0.3.2.r7.g2b4501a-1 ;;
    mise-bin) version=2026.11.2-1 ;;
    *) version=1.0-1 ;;
  esac
  package_dir="$audit_root/var/lib/pacman/local/$package-$version"
  mkdir -p "$package_dir"
  printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%ARCH%%\naarch64\n' "$package" "$version" >"$package_dir/desc"
done

# A tiny real shallow checkout gives the strict manifest actual Git evidence.
# The shared branch/index are never modified, and no remote fetch occurs.
seed="$test_tmp/source-seed"
mkdir -p "$seed/image"
cp "$ROOT/image/omarchy-pkgs.commit" "$seed/image/"
printf '/build-output-rpi4/\n' >"$seed/.gitignore"
git -C "$seed" init -q -b main
git -C "$seed" add .
git -C "$seed" -c user.name='Audit fixture' -c user.email=fixture@example.invalid commit -qm 'Fixture source'
git clone --quiet --no-local --depth 1 "$seed" "$audit_root/opt/omarchy-4-pi"
git -C "$audit_root/opt/omarchy-4-pi" remote set-url origin https://github.com/pkyanam/omarchy-4-pi.git
mkdir "$audit_root/opt/omarchy-4-pi/build-output-rpi4"
cp "$ROOT/image/omarchy-pkgs.commit" "$audit_root/opt/omarchy-4-pi/build-output-rpi4/"
node_bundle="$audit_root/var/lib/omarchy/provisioning/packages/node-v24.0.0-linux-arm64.tar.gz"
printf 'checksum-covered offline bundle fixture\n' >"$node_bundle"

python3 - "$ROOT" "$audit_root" "$test_tmp/provenance.json" <<'PY'
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("manifest", Path(sys.argv[1]) / "image/rpi4-manifest.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
root = Path(sys.argv[2])
source = root / "opt/omarchy-4-pi"
commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
provenance = Path(sys.argv[3])
provenance.write_text(json.dumps({"source_commit": commit, "source_branch": "main", "source_origin": "https://github.com/pkyanam/omarchy-4-pi.git", "source_tracking_commit": commit, "source_dirty": False, "source_tree_sha256": m.tree_digest(source), "build_kind": "candidate"}))
m.write(root, provenance, "https://base.invalid/ArchLinuxARM-rpi-aarch64-latest.tar.gz", "a" * 64, "minimal")
PY
manifest="$audit_root/usr/share/omarchy-rpi4/build-manifest.json"
audit_status=0
"$BASH" "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-ok" 2>&1 || audit_status=$?
if (( EUID != 0 )); then
  (( audit_status != 0 )) || fail "unprivileged image state must fail the real rootfs audit"
  python3 - "$test_tmp/audit-ok" <<'PY_AUDIT'
from pathlib import Path
import sys
log = Path(sys.argv[1]).read_text()
failures = [line for line in log.splitlines() if line.startswith("not ok - ")]
expected = ["not ok - image state is root-owned and factory pacman private identity is absent"]
if failures != expected or "Untrusted image target/keyring/queue state" not in log:
  raise SystemExit("Unexpected rootfs fixture failures:\n" + log)
PY_AUDIT
  pass "rootfs audit rejects unprivileged image ownership; all other 4.5 fixture invariants pass"
  skip "rootfs audit fixture requires root-owned image state; run sudo bash test/shell.d/raspberry-pi-test.sh --rootfs-audit-only"
  exit 0
fi
(( audit_status == 0 )) || fail "complete 4.5 rootfs fixture must pass the strict audit" "$(cat "$test_tmp/audit-ok")"
grep -F 'PASS:' "$test_tmp/audit-ok" >/dev/null || fail "image root audit reports its passing invariant count"
pass "image root audit accepts a complete stable 4.5 ARM64 payload with strict provenance and trusted first-boot state"

# Each fault starts from the passing fixture above. Run the actual full audit
# and demand the relevant failure; no audit or schema check is mocked.
reject_audit() {
  local label=$1 diagnostic=$2
  if "$BASH" "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-$label" 2>&1; then
    fail "rootfs audit must reject $label"
  fi
  grep -F "$diagnostic" "$test_tmp/audit-$label" >/dev/null ||
    fail "rootfs audit must diagnose $label" "$(cat "$test_tmp/audit-$label")"
}

wifi_firmware="$audit_root/usr/lib/firmware/updates/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.bin"
mv "$wifi_firmware" "$test_tmp/wifi-payload"
ln -s missing-firmware.bin "$wifi_firmware"
reject_audit wifi 'Pi 4 Wi-Fi firmware resolves to an installed payload'
rm "$wifi_firmware"
mv "$test_tmp/wifi-payload" "$wifi_firmware"
pass "image root audit rejects unresolved Pi 4 wireless firmware"

for dependency in owner-growth sddm-owner owner-hardware; do
  case $dependency in
    owner-growth)
      file="$audit_root/etc/systemd/system/omarchy-provision-owner.service.d/10-rpi4-grow-root.conf"
      unit=omarchy-rpi4-grow-root.service
      diagnostic='owner provisioning requires successful root expansion' ;;
    sddm-owner)
      file="$audit_root/etc/systemd/system/sddm.service.d/10-rpi4-owner-setup.conf"
      unit=omarchy-provision-owner.service
      diagnostic='SDDM requires successful owner provisioning' ;;
    owner-hardware)
      file="$audit_root/etc/systemd/system/omarchy-provision-owner.service.d/20-rpi4-image-hardware.conf"
      unit=omarchy-provision-hardware.service
      diagnostic='owner setup requires successful per-device keyring/hardware setup' ;;
  esac
  cp "$file" "$test_tmp/complete-dependency.conf"
  sed -i.bak "/^Requires=$unit$/d" "$file"
  reject_audit "$dependency" "$diagnostic"
  mv "$test_tmp/complete-dependency.conf" "$file"
done
pass "image root audit rejects fail-open growth, hardware and display-manager dependencies"

cp "$node_bundle" "$test_tmp/complete-node"
printf 'corrupted\n' >>"$node_bundle"
reject_audit node 'ARM64 Node.js bundle matches build provenance'
mv "$test_tmp/complete-node" "$node_bundle"
pass "image root audit rejects a corrupted offline Node.js bundle"

for fault in inventory version; do
  cp "$manifest" "$test_tmp/complete-manifest.json"
  python3 - "$manifest" "$fault" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
if sys.argv[2] == "inventory":
  data["packages"] = [item for item in data["packages"] if item["name"] != "omarchy"]
else:
  next(item for item in data["packages"] if item["name"] == "omarchy")["version"] = "9.9-9"
path.write_text(json.dumps(data))
PY
  reject_audit "$fault" 'build manifest records every installed package and exact version'
  mv "$test_tmp/complete-manifest.json" "$manifest"
done
pass "image root audit rejects incomplete inventories and incorrect package versions in valid JSON"

printf '\076\000' | dd of="$audit_root/usr/bin/quickshell" bs=1 seek=18 conv=notrunc 2>/dev/null
reject_audit executable 'Quickshell executable is AArch64'
cp "$audit_root/usr/bin/Hyprland" "$audit_root/usr/bin/quickshell"
pass "image root audit rejects an incompatible desktop executable"

package_dir="$audit_root/var/lib/pacman/local/linux-firmware-nvidia-1.0-1"
mkdir -p "$package_dir"
printf '%%NAME%%\nlinux-firmware-nvidia\n\n%%VERSION%%\n1.0-1\n\n%%ARCH%%\nany\n' >"$package_dir/desc"
reject_audit firmware 'non-Pi firmware package linux-firmware-nvidia is absent'
rm -rf "$package_dir"
pass "image root audit rejects PC-only firmware bloat"

touch "$audit_root/etc/._shadow"
reject_audit appledouble 'macOS metadata sidecars are absent'
rm "$audit_root/etc/._shadow"
pass "image root audit rejects macOS metadata sidecars"

chmod o+w "$audit_root/var/lib/omarchy/image/target"
reject_audit target-mode 'image state is root-owned and factory pacman private identity is absent'
chmod o-w "$audit_root/var/lib/omarchy/image/target"
mkdir "$audit_root/etc/pacman.d/gnupg"
reject_audit factory-keyring 'Factory pacman identity must be absent'
rmdir "$audit_root/etc/pacman.d/gnupg"
pass "image root audit rejects writable first-boot state and retained factory pacman identity"

mv "$audit_boot/Image" "$test_tmp/Linux-Image"
reject_audit linux-image 'AArch64 Linux image loaded by U-Boot is present'
mv "$test_tmp/Linux-Image" "$audit_boot/Image"
pass "image root audit requires the Linux payload separately from firmware-loaded U-Boot"

mkdir -p "$audit_root/usr/lib/systemd/zram-generator.conf.d"
printf '[zram0]\nzram-size = ram\n' >"$audit_root/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf"
reject_audit vendor-zram 'generic ARM zram does not override Pi memory/compressor policy'
rm "$audit_root/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf"
pass "image root audit rejects vendor zram overriding the Pi memory policy"
