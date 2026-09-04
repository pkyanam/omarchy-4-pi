#!/bin/bash

# Fail closed unless a mounted image contains the complete, ARM-native Omarchy
# 4 Pi boot, provisioning, graphics, and Quattro desktop payload.

set -euo pipefail

checks=0
failures=0

usage() {
  echo "Usage: $0 ROOT_MOUNT [BOOT_MOUNT]" >&2
  exit 64
}

pass() {
  checks=$((checks + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'not ok - %s\n' "$1" >&2
}

require_file() {
  local path="$1" description="$2"
  if [[ -f $path ]]; then
    pass "$description"
  else
    fail "$description (missing ${path#"$root"})"
  fi
}

require_executable() {
  local path="$1" description="$2"
  if [[ -x $path ]]; then
    pass "$description"
  else
    fail "$description (missing or not executable: ${path#"$root"})"
  fi
}

require_line() {
  local path="$1" expected="$2" description="$3"
  if [[ -f $path ]] && grep -Fx "$expected" "$path" >/dev/null; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_function_line() {
  local path="$1" function_name="$2" expected="$3" description="$4"
  if [[ -f $path ]] && awk -v function_name="$function_name" -v expected="$expected" '
    $0 == function_name "() {" { in_function = 1; next }
    in_function && $0 == "}" { exit }
    in_function {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == expected) found = 1
    }
    END { exit !found }
  ' "$path"; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_unit_link() {
  local path="$1" unit="$2" description="$3" target=""
  [[ -L $path ]] && target=$(readlink "$path")
  if [[ ${target##*/} == "$unit" ]]; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_aarch64_elf() {
  local path="$1" description="$2" magic="" machine=""
  if [[ -f $path ]]; then
    magic=$(od -An -tx1 -N4 "$path" | tr -d ' \n')
    machine=$(od -An -tx1 -j18 -N2 "$path" | tr -d ' \n')
  fi
  if [[ $magic == "7f454c46" && $machine == "b700" ]]; then
    pass "$description"
  else
    fail "$description (expected an AArch64 ELF at ${path#"$root"})"
  fi
}

pacman_field() {
  local description_file="$1" field="$2"
  awk -v marker="%$field%" '$0 == marker { getline; print; exit }' "$description_file"
}

require_package() {
  local wanted="$1" description_file name arch version
  for description_file in "$root"/var/lib/pacman/local/*/desc; do
    [[ -f $description_file ]] || continue
    name=$(pacman_field "$description_file" NAME)
    [[ $name == "$wanted" ]] || continue
    arch=$(pacman_field "$description_file" ARCH)
    version=$(pacman_field "$description_file" VERSION)
    if [[ $arch == "aarch64" || $arch == "any" ]]; then
      pass "package $wanted $version is $arch"
    else
      fail "package $wanted has incompatible architecture ${arch:-unknown}"
    fi
    return
  done
  fail "required package $wanted is installed"
}

forbid_package() {
  local unwanted="$1" description_file name
  for description_file in "$root"/var/lib/pacman/local/*/desc; do
    [[ -f $description_file ]] || continue
    name=$(pacman_field "$description_file" NAME)
    if [[ $name == "$unwanted" ]]; then
      fail "non-Pi firmware package $unwanted is absent"
      return
    fi
  done
  pass "non-Pi firmware package $unwanted is absent"
}

(( $# >= 1 && $# <= 2 )) || usage
root=${1%/}
boot=${2:-$root/boot}
boot=${boot%/}
[[ -d $root && -d $boot ]] || usage

printf 'Omarchy 4 Pi mounted-root audit\n'

require_file "$boot/kernel8.img" "Pi ARM64 kernel is present"
require_file "$boot/initramfs-linux.img" "Pi initramfs is present"
require_file "$boot/bcm2711-rpi-4-b.dtb" "Pi 4 device tree is present"
require_file "$boot/boot.scr" "Arch Linux ARM boot script is present"
require_file "$boot/start4.elf" "Pi 4 firmware is present"
appledouble_files=$(find "$root" "$boot" -xdev -type f -name '._*' -print 2>/dev/null || true)
if [[ -z $appledouble_files ]]; then
  pass "macOS metadata sidecars are absent"
else
  fail "macOS metadata sidecars are absent: ${appledouble_files//$'\n'/, }"
fi
require_line "$boot/config.txt" "dtoverlay=vc4-kms-v3d" "full VC4 KMS is enabled"
require_line "$boot/config.txt" "max_framebuffers=2" "two KMS framebuffers are enabled"
require_line "$boot/config.txt" "disable_fw_kms_setup=1" "firmware modesetting is disabled"
require_line "$boot/config.txt" "dtparam=audio=on" "Pi onboard audio is enabled"

require_line "$root/etc/fstab" "LABEL=omarchyroot /     ext4 defaults,noatime 0 1" "root filesystem mounts by label"
require_line "$root/etc/fstab" "LABEL=OMARCHYBOOT /boot vfat defaults,noatime 0 2" "boot filesystem mounts by label"
require_line "$root/etc/modules-load.d/omarchy-rpi.conf" "vc4" "VC4 kernel module is configured"
require_line "$root/etc/modules-load.d/omarchy-rpi.conf" "v3d" "V3D kernel module is configured"
require_line "$root/etc/modules-load.d/omarchy-rpi.conf" "raspberrypi_hwmon" "Pi under-voltage sensor is configured"
require_line "$root/etc/pacman.conf" "Architecture = aarch64" "pacman remains pinned to aarch64"
if [[ -f $root/etc/pacman.d/mirrorlist ]] && grep -F 'mirror.archlinuxarm.org' "$root/etc/pacman.d/mirrorlist" >/dev/null; then
  pass "Arch Linux ARM mirrors remain configured"
else
  fail "Arch Linux ARM mirrors remain configured"
fi

root_password=""
[[ -f $root/etc/shadow ]] && root_password=$(awk -F: '$1 == "root" { print $2; exit }' "$root/etc/shadow")
if [[ $root_password == "!"* || $root_password == "*"* ]]; then
  pass "root password is locked"
else
  fail "root password is locked"
fi

factory_users=""
if [[ -f $root/etc/passwd ]]; then
  factory_users=$(awk -F: '$1 == "alarm" || $1 == "omarchy-builder" || ($3 >= 1000 && $3 < 60000) { print $1 }' "$root/etc/passwd")
fi
if [[ -z $factory_users ]]; then
  pass "image has no factory or pre-created owner account"
else
  fail "image has unexpected login accounts: ${factory_users//$'\n'/, }"
fi

if [[ -f $root/etc/machine-id && ! -s $root/etc/machine-id ]]; then
  pass "machine identity is blank for first boot"
else
  fail "machine identity is blank for first boot"
fi

ssh_host_keys=$(find "$root/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*_key' -print 2>/dev/null || true)
if [[ -z $ssh_host_keys ]]; then
  pass "factory SSH host keys are absent"
else
  fail "factory SSH host keys are absent"
fi

require_file "$root/var/lib/omarchy/provisioning/pending" "owner provisioning is armed"
require_file "$root/var/lib/omarchy/provisioning/grow-root-pending" "root expansion is armed"
require_executable "$root/usr/bin/omarchy-rpi4-grow-root" "root expansion command is installed"
require_executable "$root/usr/bin/omarchy-rpi4-imager-preseed" "Imager preseed parser is installed"
require_executable "$root/usr/bin/omarchy-provision-owner" "owner provisioner is installed"
require_function_line "$root/usr/bin/omarchy-provision-owner" run_imager_setup 'apply_keyboard "$keyboard"' "unattended owner setup passes the Imager keymap"
require_function_line "$root/usr/bin/omarchy-provision-owner" configure_hostname 'hostnamectl set-hostname "$hostname"' "owner hostname is applied through systemd"
require_line "$root/etc/systemd/system/avahi-daemon.service.d/10-rpi4-owner-hostname.conf" 'After=omarchy-provision-owner.service' "mDNS waits for the owner hostname"
require_function_line "$root/usr/bin/omarchy-provision-owner" configure_imager_network 'nmcli connection reload >>"$LOG_FILE" 2>&1 || true' "Imager Wi-Fi reloads NetworkManager profiles"
require_function_line "$root/usr/bin/omarchy-provision-owner" configure_imager_ssh 'systemctl enable --now sshd.service' "Imager SSH enables the server"
require_function_line "$root/usr/bin/omarchy-provision-owner" configure_imager_ssh 'ufw limit 22/tcp comment omarchy-imager-sshd >/dev/null' "Imager SSH opens a rate-limited firewall rule"
require_line "$root/etc/systemd/system/omarchy-provision-owner.service.d/10-rpi4-grow-root.conf" 'Requires=omarchy-rpi4-grow-root.service' "owner provisioning requires successful root expansion"
require_line "$root/etc/systemd/system/omarchy-provision-owner.service.d/10-rpi4-grow-root.conf" 'After=omarchy-rpi4-grow-root.service' "owner provisioning waits for root expansion"
require_line "$root/etc/systemd/system/sddm.service.d/10-rpi4-owner-setup.conf" 'Requires=omarchy-provision-owner.service' "SDDM requires successful owner provisioning"
require_line "$root/etc/systemd/system/sddm.service.d/10-rpi4-owner-setup.conf" 'After=omarchy-provision-owner.service' "SDDM waits for owner provisioning"
require_unit_link "$root/etc/systemd/system/multi-user.target.wants/omarchy-rpi4-grow-root.service" "omarchy-rpi4-grow-root.service" "root expansion service is enabled"
require_unit_link "$root/etc/systemd/system/multi-user.target.wants/omarchy-provision-owner.service" "omarchy-provision-owner.service" "owner provisioning service is enabled"
require_unit_link "$root/etc/systemd/system/display-manager.service" "sddm.service" "SDDM display manager is enabled"
require_unit_link "$root/etc/systemd/system/multi-user.target.wants/NetworkManager.service" "NetworkManager.service" "NetworkManager is enabled"
require_unit_link "$root/etc/systemd/system/NetworkManager-wait-online.service" "null" "network association cannot delay the desktop"
require_unit_link "$root/etc/systemd/system/multi-user.target.wants/avahi-daemon.service" "avahi-daemon.service" "Avahi mDNS hostname discovery is enabled"
require_unit_link "$root/etc/systemd/system/bluetooth.target.wants/bluetooth.service" "bluetooth.service" "Bluetooth service is enabled"
require_unit_link "$root/etc/systemd/user/sockets.target.wants/pipewire.socket" "pipewire.socket" "PipeWire audio socket is enabled"
require_unit_link "$root/etc/systemd/user/sockets.target.wants/pipewire-pulse.socket" "pipewire-pulse.socket" "PulseAudio compatibility socket is enabled"
require_unit_link "$root/etc/systemd/user/pipewire.service.wants/wireplumber.service" "wireplumber.service" "WirePlumber session manager is enabled"

require_executable "$root/usr/bin/Hyprland" "Hyprland compositor is installed"
require_executable "$root/usr/bin/quickshell" "Quickshell runtime is installed"
require_executable "$root/usr/bin/omarchy-shell" "Omarchy shell launcher is installed"
require_executable "$root/usr/bin/ttfx" "screensaver renderer is installed"
require_executable "$root/usr/bin/vcgencmd" "Raspberry Pi power diagnostic is installed"
require_executable "$root/usr/bin/omarchy-pi-check" "Pi hardware acceptance command is installed"
require_executable "$root/usr/bin/omarchy-pi-display" "Pi display recovery command is installed"
require_executable "$root/usr/bin/omarchy-pi-report" "Pi agent-readable diagnostics are installed"
require_executable "$root/usr/bin/omarchy-pi-run" "Pi workload budgeting command is installed"
require_executable "$root/usr/bin/omarchy-update-rpi4-guard" "Pi update source and architecture guard is installed"
require_file "$root/usr/lib/firmware/updates/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.bin" "Pi 4 Wi-Fi firmware resolves to an installed payload"
require_file "$root/usr/lib/firmware/updates/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt" "Pi 4 Wi-Fi board calibration is installed"
require_file "$root/usr/lib/firmware/updates/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.clm_blob" "Pi 4 Wi-Fi regulatory data is installed"
require_file "$root/usr/lib/firmware/updates/brcm/BCM4345C0.hcd" "Pi 4 Bluetooth firmware is installed"
require_file "$root/usr/share/licenses/broadcom/cypress/LICENSE" "Pi wireless firmware redistribution notice is retained"
require_file "$root/usr/share/omarchy/shell/shell.qml" "Quattro shell payload is installed"
require_file "$root/usr/share/omarchy-rpi4/hyprland-config-verified" "ARM64 Hyprland accepted the Pi owner configuration"
require_file "$root/usr/local/share/wayland-sessions/omarchy.desktop" "Omarchy Wayland session is installed"
require_line "$root/usr/local/share/wayland-sessions/omarchy.desktop" "Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop" "Omarchy session starts Hyprland through uwsm"
require_file "$root/etc/skel/.config/hypr/hyprland.lua" "new users receive the Hyprland configuration"
require_file "$root/usr/share/omarchy/default/hypr/raspberry-pi.lua" "Pi compositor compatibility profile is installed"
require_file "$root/usr/share/sddm/themes/omarchy/Main.qml" "Omarchy SDDM theme is installed"

for package in \
  hyprland quickshell mesa vulkan-broadcom linux-aarch64 raspberrypi-utils firmware-raspberrypi \
  sddm networkmanager wpa_supplicant iw wireless-regdb avahi nss-mdns openssh ufw bluez bluez-tools bluez-utils \
  alsa-utils pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber \
  uwsm chromium foot ttfx omarchy omarchy-settings; do
  require_package "$package"
done

incompatible_packages=""
for description_file in "$root"/var/lib/pacman/local/*/desc; do
  [[ -f $description_file ]] || continue
  name=$(pacman_field "$description_file" NAME)
  arch=$(pacman_field "$description_file" ARCH)
  if [[ $arch != "aarch64" && $arch != "any" ]]; then
    incompatible_packages+="${name:-unknown}:${arch:-unknown}"$'\n'
  fi
done
if [[ -z $incompatible_packages ]]; then
  pass "all installed packages are aarch64 or architecture-independent"
else
  fail "incompatible package records found: ${incompatible_packages//$'\n'/, }"
fi

require_aarch64_elf "$root/usr/bin/Hyprland" "Hyprland executable is AArch64"
require_aarch64_elf "$root/usr/bin/quickshell" "Quickshell executable is AArch64"
require_aarch64_elf "$root/usr/bin/foot" "terminal executable is AArch64"

require_file "$root/usr/share/omarchy-rpi4/build-manifest.json" "embedded build manifest is present"
manifest="$root/usr/share/omarchy-rpi4/build-manifest.json"
if [[ -f $manifest ]] && grep -F '"source_dirty": false' "$manifest" >/dev/null; then
  pass "release source tree was clean"
else
  fail "release source tree was clean"
fi
if [[ -f $manifest ]] && grep -Eq '"source_commit": "[0-9a-f]{40}"' "$manifest"; then
  pass "port source has exact provenance"
else
  fail "port source has exact provenance"
fi
if [[ -f $manifest ]] && grep -Eq '"omarchy_pkgs_commit": "[0-9a-f]{40}"' "$manifest"; then
  pass "Omarchy package recipes have exact provenance"
else
  fail "Omarchy package recipes have exact provenance"
fi
if [[ -f $manifest ]] && grep -Eq '"base_sha256": "[0-9a-f]{64}"' "$manifest" &&
  grep -F '"base_signing_key": "68B3537F39A313B3E574D06777193F152BDBE6A6"' "$manifest" >/dev/null; then
  pass "signed Arch Linux ARM base has exact provenance"
else
  fail "signed Arch Linux ARM base has exact provenance"
fi

node_bundle=""
node_bundle_count=0
for candidate in "$root"/var/lib/omarchy/provisioning/packages/node-v*-linux-arm64.tar.gz; do
  [[ -f $candidate ]] || continue
  node_bundle=$candidate
  node_bundle_count=$((node_bundle_count + 1))
done
if (( node_bundle_count == 1 )); then
  node_bundle_name=${node_bundle##*/}
  node_bundle_sha=$(sha256sum "$node_bundle" | awk '{ print $1 }')
  if grep -F "\"node_bundle\": {\"filename\": \"$node_bundle_name\", \"sha256\": \"$node_bundle_sha\"}" \
    "$manifest" >/dev/null; then
    pass "verified ARM64 Node.js bundle is staged for offline owner setup"
  else
    fail "ARM64 Node.js bundle matches build provenance"
  fi
else
  fail "exactly one ARM64 Node.js bundle is staged for offline owner setup"
fi
if find "$root/var/lib/omarchy/provisioning/packages" -maxdepth 1 -type f \
  -name 'node-v*-linux-x64.tar.gz' -print -quit 2>/dev/null | grep -q .; then
  fail "x86_64 Node.js bundles are absent from the Pi image"
else
  pass "x86_64 Node.js bundles are absent from the Pi image"
fi

installed_package_inventory=""
for description_file in "$root"/var/lib/pacman/local/*/desc; do
  [[ -f $description_file ]] || continue
  name=$(pacman_field "$description_file" NAME)
  version=$(pacman_field "$description_file" VERSION)
  installed_package_inventory+="$name"$'\t'"$version"$'\n'
done
installed_package_inventory=$(printf '%s' "$installed_package_inventory" | LC_ALL=C sort)
manifest_package_inventory=""
if [[ -f $manifest ]]; then
  manifest_package_inventory=$(sed -n \
    's/^    {"name": "\([^"]*\)", "version": "\([^"]*\)"},*$/\1\	\2/p' \
    "$manifest" | LC_ALL=C sort)
fi
if [[ -n $installed_package_inventory && $manifest_package_inventory == "$installed_package_inventory" ]]; then
  pass "build manifest records every installed package and exact version"
else
  fail "build manifest records every installed package and exact version"
fi

require_file "$root/opt/omarchy-4-pi/.git/shallow" "update checkout uses bounded Git history"

require_package linux-firmware-broadcom
for package in linux-firmware linux-firmware-amdgpu linux-firmware-atheros linux-firmware-cirrus linux-firmware-intel linux-firmware-mediatek linux-firmware-nvidia linux-firmware-other linux-firmware-radeon; do
  forbid_package "$package"
done

if (( failures )); then
  printf 'FAILED: %d of %d checks failed\n' "$failures" "$checks" >&2
  exit 1
fi

printf 'PASS: %d image invariants verified\n' "$checks"
