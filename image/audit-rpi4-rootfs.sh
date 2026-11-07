#!/bin/bash

# Fail closed unless a mounted image contains the complete, ARM-native Omarchy
# 4 Pi boot, provisioning, graphics, and Quattro desktop payload.

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

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

require_package() {
  local wanted=$1 arch=${installed_architectures[$1]:-} version=${installed_versions[$1]:-}
  if [[ -z $version ]]; then
    fail "required package $wanted is installed"
  elif [[ $arch == aarch64 || $arch == any ]]; then
    pass "package $wanted $version is $arch"
  else
    fail "package $wanted has incompatible architecture ${arch:-unknown}"
  fi
}

forbid_package() {
  if [[ -n ${installed_versions[$1]:-} ]]; then
    fail "non-Pi firmware package $1 is absent"
  else
    pass "non-Pi firmware package $1 is absent"
  fi
}

require_package_version() {
  if [[ ${installed_versions[$1]:-} == "$2" ]]; then
    pass "$1 matches reviewed version $2"
  else
    fail "$1 matches reviewed version $2"
  fi
}

(( $# >= 1 && $# <= 2 )) || usage
root=${1%/}
boot=${2:-$root/boot}
boot=${boot%/}
[[ -d $root && -d $boot ]] || usage

printf 'Omarchy 4 Pi mounted-root audit\n'

# Read metadata once: repeatedly starting awk for each package in every check
# makes the mounted-root gate unnecessarily expensive on a one-CPU builder.
installed_metadata=$(python3 - "$root" <<'PY_INVENTORY'
from pathlib import Path
import sys
for path in sorted((Path(sys.argv[1]) / "var/lib/pacman/local").glob("*/desc")):
  lines = path.read_text().splitlines()
  values = [lines[lines.index(f"%{field}%") + 1] for field in ("NAME", "VERSION", "ARCH")]
  if not all(value and not any(c.isspace() for c in value) for value in values):
    raise SystemExit("Malformed installed package metadata")
  print("\t".join(values))
PY_INVENTORY
)
declare -A installed_versions=() installed_architectures=()
while IFS=$'\t' read -r name version arch; do
  [[ -n $name ]] || continue
  [[ -z ${installed_versions[$name]:-} ]] || { fail "duplicate installed package $name"; continue; }
  installed_versions[$name]=$version
  installed_architectures[$name]=$arch
done <<<"$installed_metadata"

require_file "$boot/kernel8.img" "Pi firmware-loaded U-Boot is present"
require_file "$boot/Image" "AArch64 Linux image loaded by U-Boot is present"
require_file "$boot/initramfs-linux.img" "Pi initramfs is present"
require_file "$boot/bcm2711-rpi-4-b.dtb" "Pi 4 device tree is present"
require_file "$boot/dtbs/broadcom/bcm2711-rpi-4-b.dtb" "Pi 4 Linux device tree loaded by U-Boot is present"
require_file "$boot/boot.scr" "Arch Linux ARM boot script is present"
require_file "$boot/boot.txt" "Arch Linux ARM boot script source is present"
require_file "$boot/start4.elf" "Pi 4 firmware is present"
require_file "$boot/fixup4.dat" "Pi 4 firmware fixup is present"
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
if python3 - "$root/usr/share/omarchy/default/pi/firmware-config.py" "$boot/config.txt" <<'PY'
import importlib.util
from pathlib import Path
import sys
spec = importlib.util.spec_from_file_location("pi_firmware", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = Path(sys.argv[2]).read_bytes()
if module.proposed(original) != original:
  raise SystemExit("Pi boot policy is not the effective, final managed configuration")
PY
then
  pass "Pi 4 KMS/audio policy accounts for firmware sections and final priority"
else
  fail "Pi 4 KMS/audio policy accounts for firmware sections and final priority"
fi

require_line "$root/etc/fstab" "LABEL=omarchyroot /     ext4 defaults,noatime 0 1" "root filesystem mounts by label"
require_line "$root/etc/fstab" "LABEL=OMARCHYBOOT /boot vfat defaults,noatime 0 2" "boot filesystem mounts by label"
require_line "$root/etc/modules-load.d/omarchy-rpi.conf" "vc4" "VC4 kernel module is configured"
require_line "$root/etc/modules-load.d/omarchy-rpi.conf" "v3d" "V3D kernel module is configured"
require_line "$root/etc/modules-load.d/omarchy-rpi.conf" "raspberrypi_hwmon" "Pi under-voltage sensor is configured"
require_line "$root/etc/pacman.conf" "Architecture = aarch64" "pacman remains pinned to aarch64"
require_line "$root/etc/pacman.conf" "SigLevel = Required DatabaseOptional" "package signatures remain required"
require_line "$root/etc/omarchy-rpi4.conf" "OMARCHY_RPI4_PACKAGE_POLICY=stable-4.5" "image uses the reviewed stable 4.5 ARM closure"
if [[ -f $root/etc/pacman.d/mirrorlist ]] && grep -Fx 'Server = https://arm-stable-mirror.omarchy.org/$arch/$repo' "$root/etc/pacman.d/mirrorlist" >/dev/null; then
  pass "coherent stable Arch Linux ARM mirrors remain configured"
else
  fail "coherent stable Arch Linux ARM mirrors remain configured"
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
require_file "$root/var/lib/omarchy/image/pacman-keyring" "per-device pacman identity is armed"
require_file "$root/var/lib/omarchy/image/deferred-steps" "hardware setup remains deferred to the Pi"
require_line "$root/var/lib/omarchy/image/target" "format=1" "trusted 4.5 image target format is staged"
require_line "$root/var/lib/omarchy/image/target" "platform=aarch64" "image identifies its target rather than its builder"
require_line "$root/var/lib/omarchy/image/deferred-steps" "install/hardware/raspberry-pi.sh" "Pi hardware setup remains queued for the real device"
if python3 - "$root" <<'PY'
from pathlib import Path
import stat
import sys
root = Path(sys.argv[1])
for name in ("var/lib/omarchy/image", "var/lib/omarchy/image/target", "var/lib/omarchy/image/pacman-keyring", "var/lib/omarchy/image/deferred-steps"):
  path = root / name
  info = path.lstat()
  if path.is_symlink() or info.st_uid != 0 or stat.S_IMODE(info.st_mode) & 0o022:
    raise SystemExit("Untrusted image target/keyring/queue state")
if (root / "etc/pacman.d/gnupg").exists() or (root / "etc/pacman.d/gnupg").is_symlink():
  raise SystemExit("Factory pacman identity must be absent")
PY
then
  pass "image state is root-owned and factory pacman private identity is absent"
else
  fail "image state is root-owned and factory pacman private identity is absent"
fi
require_file "$root/usr/share/pacman/keyrings/archlinuxarm.gpg" "packaged ALARM public trust remains available offline"
require_file "$root/usr/share/pacman/keyrings/omarchy.gpg" "packaged Omarchy public trust remains available offline"
require_executable "$root/usr/bin/omarchy-provision-hardware" "deferred hardware/keyring runner is installed"
require_unit_link "$root/etc/systemd/system/multi-user.target.wants/omarchy-provision-hardware.service" "omarchy-provision-hardware.service" "hardware/keyring setup service is enabled"
require_line "$root/etc/systemd/system/omarchy-provision-owner.service.d/20-rpi4-image-hardware.conf" 'Requires=omarchy-provision-hardware.service' "owner setup requires successful per-device keyring/hardware setup"
require_line "$root/etc/systemd/system/omarchy-provision-owner.service.d/20-rpi4-image-hardware.conf" 'After=omarchy-provision-hardware.service' "owner setup waits for per-device keyring/hardware setup"
require_line "$root/etc/systemd/system/omarchy-provision-owner.service.d/20-rpi4-image-hardware.conf" 'Environment=OMARCHY_PATH=/usr/share/omarchy' "owner setup has the runtime path before uwsm exists"
require_line "$root/etc/systemd/system/omarchy-provision-hardware.service.d/10-rpi4-grow-root.conf" 'Requires=omarchy-rpi4-grow-root.service' "hardware/keyring setup requires root growth"
require_line "$root/etc/systemd/system/omarchy-provision-hardware.service.d/10-rpi4-grow-root.conf" 'After=omarchy-rpi4-grow-root.service' "hardware/keyring setup waits for root growth"
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
require_executable "$root/usr/bin/omarchy-pi-tune" "Pi clock trial command is installed"
require_executable "$root/usr/bin/omarchy-pi-benchmark" "Pi guarded CPU benchmark is installed"
require_file "$root/usr/share/omarchy/default/pi/tune.py" "Pi clock trial implementation is packaged"
require_file "$root/usr/share/omarchy/default/pi/benchmark.py" "Pi CPU benchmark implementation is packaged"
require_file "$root/usr/share/omarchy/default/pi/build-budget.sh" "Pi compiler budget implementation is packaged"
require_file "$root/etc/systemd/system/omarchy-pi-tune-guard.service" "Pi clock recovery unit is available"
require_executable "$root/usr/bin/omarchy-pi-cpu-policy" "Pi boot CPU policy is installed"
require_file "$root/etc/systemd/system/omarchy-pi-cpu-policy.service" "Pi load-responsive CPU policy unit is available"
require_unit_link "$root/etc/systemd/system/multi-user.target.wants/omarchy-pi-cpu-policy.service" "omarchy-pi-cpu-policy.service" "Pi load-responsive boot CPU policy is enabled"
require_line "$root/etc/makepkg.conf.d/50-omarchy-pi.conf" "source /usr/share/omarchy/default/pi/build-budget.sh" "Pi local package builds use memory-aware defaults"
require_line "$root/etc/systemd/journald.conf.d/50-omarchy-pi.conf" "SystemMaxUse=128M" "Pi persistent journal has a bounded SD-card budget"
require_line "$root/etc/systemd/zram-generator.conf.d/50-omarchy-pi.conf" "zram-size = ram / 2" "Pi compressed swap is configured independently of upstream ARM packaging"
if [[ ! -e $root/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf ]] ||
  [[ -L $root/etc/systemd/zram-generator.conf.d/90-omarchy.conf && $(readlink "$root/etc/systemd/zram-generator.conf.d/90-omarchy.conf") == /dev/null ]]; then
  pass "generic ARM zram does not override Pi memory/compressor policy"
else
  fail "generic ARM zram does not override Pi memory/compressor policy"
fi
require_line "$root/etc/systemd/user/app.slice.d/50-omarchy-pi.conf" "ManagedOOMMemoryPressure=kill" "Pi application scopes have a memory-pressure escape path"
require_line "$root/etc/systemd/oomd.conf.d/50-omarchy-pi.conf" "DefaultMemoryPressureDurationSec=20s" "Pi oomd waits for sustained application pressure"
require_line "$root/etc/sysctl.d/99-omarchy-pi-writeback.conf" "vm.dirty_bytes=134217728" "Pi SD-card dirty-write bursts are bounded"
if [[ ! -e $root/var/lib/omarchy/pi-tune/state.json ]] && ! grep -Eq '^[[:space:]]*(arm_freq|over_voltage[^=]*|force_turbo|temp_limit)[[:space:]]*=' "$boot/config.txt"; then
  pass "image ships without an applied CPU overclock or thermal override"
else
  fail "image must ship without applied clock trials or thermal overrides"
fi
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
require_aarch64_elf "$root/usr/lib/omarchy-hyprland-titlebars/titlebars.so" "floating titlebar plugin is AArch64"
require_file "$root/usr/share/sddm/themes/omarchy/Main.qml" "Omarchy SDDM theme is installed"

for package in \
  hyprland quickshell mesa vulkan-broadcom linux-aarch64 raspberrypi-utils firmware-raspberrypi \
  sddm networkmanager wpa_supplicant iw wireless-regdb avahi nss-mdns openssh ufw bluez bluez-tools bluez-utils \
  alsa-utils pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber \
  uwsm chromium foot ttfx omarchy omarchy-settings omarchy-keyring archlinuxarm-keyring \
  omasnap owe omarchy-hyprland-titlebars omarchy-speedtest omarchy-power-profiles-daemon \
  monologue hype disktree-bin gliff signed mise-bin rtkit zram-generator cloud-guest-utils python \
  fcitx5 fcitx5-chewing fcitx5-chinese-addons fcitx5-gtk fcitx5-hangul fcitx5-mozc fcitx5-qt fcitx5-table-extra; do
  require_package "$package"
done
require_package_version omarchy 4.5.0.pi4.1-1
require_package_version omarchy-settings 4.5.0.pi4.1-1
require_package_version hyprland 0.56.2-7
require_package_version omarchy-hyprland-titlebars 0.2.2-2
require_package_version quickshell 0.3.2.r7.g2b4501a-1
for unwanted in 00-omarchy-hooks.conf omarchy_hooks.conf thunderbolt_module.conf omarchy_vconsole.conf i2c_hid_of_module.conf; do
  if [[ -e $root/etc/mkinitcpio.conf.d/$unwanted ]]; then
    fail "generic ARM boot fragment $unwanted is absent"
  else
    pass "generic ARM boot fragment $unwanted is absent"
  fi
done

incompatible_packages=""
for name in "${!installed_architectures[@]}"; do
  arch=${installed_architectures[$name]}
  if [[ $arch != "aarch64" && $arch != "any" ]]; then
    incompatible_packages+="$name:$arch"$'\n'
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
if python3 "$script_dir/rpi4-manifest.py" validate "$manifest" "$root"; then
  pass "strict build provenance matches source, recipes, mirrors, Node bundle, and installed inventory"
else
  fail "strict build provenance matches source, recipes, mirrors, Node bundle, and installed inventory"
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
