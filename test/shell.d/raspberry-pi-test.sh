#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

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

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$ROOT/bin:$PATH" \
OMARCHY_RPI_MODEL_PATH="$model" \
OMARCHY_RPI_CONFIG_PATH="$boot_config" \
OMARCHY_RPI_MODULES_PATH="$modules_file" \
  bash -euo pipefail "$ROOT/install/hardware/raspberry-pi.sh"

grep -Fx 'dtoverlay=vc4-kms-v3d' "$boot_config" >/dev/null || fail "Pi hardware setup enables full VC4 KMS"
grep -Fx 'max_framebuffers=2' "$boot_config" >/dev/null || fail "Pi hardware setup configures two KMS framebuffers"
grep -Fx 'disable_fw_kms_setup=1' "$boot_config" >/dev/null || fail "Pi hardware setup delegates modesetting to KMS"
[[ $(grep -c '^dtoverlay=vc4-kms-v3d$' "$boot_config") == "1" ]] || fail "Pi hardware setup adds KMS exactly once"
printf 'vc4\nv3d\n' | cmp -s - "$modules_file" || fail "Pi hardware setup loads the VC4 and V3D modules"
grep -Fx 'vulkan-broadcom' "$test_tmp/calls.log" >/dev/null || fail "Pi hardware setup installs the Broadcom Vulkan driver"
pass "Pi hardware setup configures the graphics stack"

cat >"$fake_bin/vcgencmd" <<'EOF'
#!/bin/bash
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
pass "Pi status explains Raspberry Pi power flags"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$ROOT/bin:$PATH" \
OMARCHY_RPI_MODEL_PATH="$model" \
OMARCHY_RPI_CONFIG_PATH="$boot_config" \
OMARCHY_RPI_MODULES_PATH="$modules_file" \
  bash -euo pipefail "$ROOT/install/hardware/raspberry-pi.sh"
[[ $(grep -c '^dtoverlay=vc4-kms-v3d$' "$boot_config") == "1" ]] || fail "Pi hardware setup is idempotent"
pass "Pi hardware setup is idempotent"

grep -Fx 'Architecture = aarch64' "$ROOT/default/pacman/pacman-rpi4.conf" >/dev/null || fail "Pi pacman profile pins aarch64"
grep -F 'mirror.archlinuxarm.org/$arch/$repo' "$ROOT/default/pacman/mirrorlist-rpi4" >/dev/null || fail "Pi mirrorlist uses Arch Linux ARM"
[[ $(grep -c '^Server = ' "$ROOT/default/pacman/mirrorlist-rpi4") -ge 5 ]] ||
  fail "Pi mirrorlist has enough official failover servers for long image builds"
! grep -q 'omarchy.org' "$ROOT/default/pacman/pacman-rpi4.conf" || fail "Pi pacman profile does not reference x86 Omarchy repositories"
pass "Pi package profile stays on Arch Linux ARM"

grep -F 'require("default.hypr.raspberry-pi")' "$ROOT/default/hypr/envs.lua" >/dev/null || fail "Hyprland loads the Pi hardware environment"
grep -F 'hl.env("AQ_NO_MODIFIERS", "1")' "$ROOT/default/hypr/raspberry-pi.lua" >/dev/null || fail "Pi Hyprland environment applies the limited-GPU workaround"
pass "Hyprland applies the Raspberry Pi graphics compatibility setting"

bash -euo pipefail "$ROOT/install/hardware/apple/fix-spi-keyboard.sh"
pass "DMI-only hardware probes are harmless on device-tree systems"

OMARCHY_ROOT_FSTYPE=ext4 \
OMARCHY_SNAPPER_CONFIG_PATH="$test_tmp/snapper/root" \
OMARCHY_SNAPPER_CONF_PATH="$test_tmp/conf.d/snapper" \
  bash -euo pipefail "$ROOT/install/config/snapper.sh" >"$test_tmp/snapper-output"
[[ ! -e $test_tmp/snapper/root ]] || fail "ext4 setup does not create an unusable Snapper configuration"
grep -F 'root filesystem is not Btrfs' "$test_tmp/snapper-output" >/dev/null || fail "ext4 setup explains why Snapper is skipped"
pass "ext4 installs skip Btrfs-only Snapper setup"

bash -n "$ROOT/install-rpi4.sh"
bash -n "$ROOT/build-packages-rpi4.sh"
bash -n "$ROOT/bin/omarchy-update-rpi4"
bash -n "$ROOT/bin/omarchy-rpi4-grow-root"
bash -n "$ROOT/bin/omarchy-pi-status"
bash -n "$ROOT/image/build-rpi4-image.sh"
bash -n "$ROOT/image/build-rpi4-image-macos.sh"
bash -n "$ROOT/image/audit-rpi4-rootfs.sh"
bash -n "$ROOT/image/generate-imager-catalog.sh"
bash -n "$ROOT/image/generate-local-imager-manifest.sh"
bash -n "$ROOT/image/open-in-rpi-imager-macos.sh"
bash -n "$ROOT/image/prepare-release-assets.sh"
pass "Raspberry Pi install, image, and update entrypoints parse"

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
  bash "$ROOT/bin/omarchy-refresh-limine") ||
  fail "Pi config refresh skips the PC bootloader without failing"
[[ ! -e $limine_test/calls ]] || fail "Pi config refresh never invokes Limine through sudo"
grep -F 'Raspberry Pi firmware boot does not use Limine' <<<"$limine_output" >/dev/null ||
  fail "Pi config refresh explains why Limine is skipped"
pass "Pi config refresh leaves the firmware boot partition alone"

grep -F 'pacman -S --asdeps --needed --noconfirm' "$ROOT/build-packages-rpi4.sh" >/dev/null ||
  fail "Raspberry Pi package builder marks temporary build dependencies removable"
grep -F 'image_size_gib >= 12' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder rejects filesystems too small for the transient Quattro install"
grep -F "startsWith(github.ref, 'refs/tags/') && '-9e'" "$ROOT/.github/workflows/build-rpi4-image.yml" >/dev/null ||
  fail "tagged image builds always select release-grade compression"
pass "image factory bounds transient package-build storage"

grep -F 'unshare --mount --propagation private' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder isolates temporary mounts in a private namespace"
grep -F 'OMARCHY_IMAGE_PRIVATE_MOUNT_NS=1' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder mount namespace re-entry is bounded"
pass "image builder prevents loop mounts from propagating to host services"

grep -F 'refusing to publish a dirty image' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder requires a strict root unmount"
grep -F 'e2fsck -fn "$(partition_path 2)"' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder verifies the completed ext4 filesystem"
grep -F 'Waiting for the root loop partition to become idle' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder tolerates bounded udev release latency"
grep -F 'fsck.vfat -n "$(partition_path 1)"' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder verifies the completed FAT filesystem"
grep -F 'zerofree "$(partition_path 2)"' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder zeroes unused ext4 blocks before compression"
grep -F 'chroot "$root_mount" mkinitcpio -P' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder fails closed when final initramfs regeneration fails"
unmount_function=$(sed -n '/^unmount_and_verify_image()/,/^}/p' "$ROOT/image/build-rpi4-image.sh")
! grep -F 'umount -R -l' <<<"$unmount_function" >/dev/null ||
  fail "image verification never follows a lazy recursive unmount"
pass "image publication requires clean filesystems"

grep -F 'git clone --quiet --no-local --depth 1' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder keeps a shallow source checkout for future updates"
grep -F 'OMARCHY_SOURCE_ORIGIN' "$ROOT/image/build-rpi4-image-macos.sh" >/dev/null ||
  fail "macOS builds pass a public source origin into their Git-free archive"
grep -F 'clone_source=$origin_url' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder reconstructs update metadata for Git-free Mac sources"
grep -F 'show-ref --verify --quiet "refs/heads/$source_branch"' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "detached release tags fall back to the public update origin"
grep -F 'COPYFILE_DISABLE=1 tar' "$ROOT/image/build-rpi4-image-macos.sh" >/dev/null ||
  fail "macOS source archives suppress AppleDouble metadata"
grep -F -- "--exclude '._*'" "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image source overlay excludes AppleDouble metadata"
grep -F 'linux-firmware-broadcom linux-firmware-realtek' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder preserves Pi and common USB adapter firmware"
grep -F 'linux-firmware-nvidia' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image builder identifies PC-only firmware for removal"
grep -F 'raspberrypi-utils' "$ROOT/install-rpi4.sh" >/dev/null ||
  fail "Pi image includes the native firmware diagnostics"
grep -F 'build/image/*.os-list.json build/image/os-list.json' \
  "$ROOT/.github/workflows/build-rpi4-image.yml" >/dev/null ||
  fail "tag releases publish Raspberry Pi Imager catalogs"
grep -F 'releases/download/$GITHUB_REF_NAME' \
  "$ROOT/.github/workflows/build-rpi4-image.yml" >/dev/null ||
  fail "tagged Imager catalogs use their immutable release URL"
grep -F 'OMARCHY_IMAGE_DOWNLOAD_BASE_URL' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image catalogs accept a release-specific download URL"
grep -F 'omarchy-pkgs.commit' "$ROOT/build-packages-rpi4.sh" >/dev/null ||
  fail "local Omarchy packages record their recipe checkout"
grep -F 'chroot "$root_mount" pacman -Q | LC_ALL=C sort' "$ROOT/image/build-rpi4-image.sh" >/dev/null ||
  fail "image manifest derives a sorted final package inventory"
pass "image builder removes download bloat without narrowing the Quattro payload"

grep -F '(( image_mode == 0 )) || max_attempts=8' "$ROOT/install-rpi4.sh" >/dev/null ||
  fail "image builds get extended resumable package retries"
pass "image package downloads tolerate transient mirror failures"

release_tmp="$test_tmp/release"
mkdir -p "$release_tmp"
printf '0123456789abcdef' >"$test_tmp/test.img.xz"
OMARCHY_RELEASE_PART_MIB=1 "$ROOT/image/prepare-release-assets.sh" \
  "$test_tmp/test.img.xz" "$release_tmp"
[[ -f $release_tmp/test.img.xz ]] || fail "small release images remain whole"
grep -q '  test.img.xz$' "$release_tmp/test.img.xz.sha256" ||
  fail "release checksums use portable basenames"

dd if=/dev/zero of="$test_tmp/large.img.xz" bs=1048576 count=2 2>/dev/null
OMARCHY_RELEASE_PART_MIB=1 "$ROOT/image/prepare-release-assets.sh" \
  "$test_tmp/large.img.xz" "$release_tmp"
[[ -f $release_tmp/large.img.xz.part-00 && -f $release_tmp/large.img.xz.part-01 ]] ||
  fail "oversized release images are split"
cat "$release_tmp"/large.img.xz.part-* >"$test_tmp/reassembled.img.xz"
cmp "$test_tmp/large.img.xz" "$test_tmp/reassembled.img.xz" ||
  fail "release image parts reassemble exactly"
pass "release assets remain under GitHub's limit and reassemble losslessly"

grep -F -- '--image' "$ROOT/install-rpi4.sh" >/dev/null || fail "installer exposes OEM image mode"
grep -F 'cloud-guest-utils' "$ROOT/install-rpi4.sh" >/dev/null || fail "image payload includes growpart"
grep -F 'Before=omarchy-provision-owner.service' \
  "$ROOT/install/provisioning/omarchy-rpi4-grow-root.service" >/dev/null ||
  fail "root growth runs before owner provisioning"
grep -Fx 'Requires=omarchy-rpi4-grow-root.service' \
  "$ROOT/install/provisioning/omarchy-provision-owner-rpi4.conf" >/dev/null ||
  fail "owner provisioning requires successful root growth"
grep -Fx 'After=omarchy-rpi4-grow-root.service' \
  "$ROOT/install/provisioning/omarchy-provision-owner-rpi4.conf" >/dev/null ||
  fail "owner provisioning waits for root growth"
grep -F 'omarchy-provision-owner.service.d/10-rpi4-grow-root.conf' \
  "$ROOT/install-rpi4.sh" >/dev/null ||
  fail "Pi image installs the root-growth dependency drop-in"
grep -F '/var/lib/omarchy/provisioning/grow-root-pending' \
  "$ROOT/bin/omarchy-rpi4-grow-root" >/dev/null || fail "root growth is guarded by a one-shot marker"
grep -F 'omarchy-rpi4-imager-preseed' "$ROOT/bin/omarchy-provision-owner" >/dev/null ||
  fail "owner setup consumes Raspberry Pi Imager settings"
awk '
  $0 == "run_imager_setup() {" { in_function = 1; next }
  in_function && $0 == "}" { exit }
  in_function && $0 ~ /^[[:space:]]*apply_keyboard "\$keyboard"[[:space:]]*$/ { found = 1 }
  END { exit !found }
' "$ROOT/bin/omarchy-provision-owner" ||
  fail "unattended owner setup applies the Imager keymap without aborting"
grep -F 'chpasswd --encrypted' "$ROOT/bin/omarchy-provision-owner" >/dev/null ||
  fail "Imager password hashes are never treated as plaintext"
grep -F 'linux-arm64' "$ROOT/install-rpi4.sh" >/dev/null ||
  fail "Pi image stages an architecture-correct offline Node.js archive"
grep -F 'aarch64|arm64) NODE_ARCH=arm64' "$ROOT/install/user/mise-work.sh" >/dev/null ||
  fail "owner finalization selects the ARM64 Node.js archive"
pass "image mode arms ordered first-boot storage growth and owner provisioning"

node_test="$test_tmp/node-owner-finalization"
node_bundle_root="$node_test/bundle/node-v24.2.0-linux-arm64"
node_mock_bin="$node_test/bin"
mkdir -p "$node_bundle_root/bin" "$node_mock_bin" "$node_test/packages" "$node_test/home"
printf '#!/bin/bash\n' >"$node_bundle_root/bin/node"
chmod +x "$node_bundle_root/bin/node"
tar -czf "$node_test/packages/node-v24.2.0-linux-arm64.tar.gz" \
  -C "$node_test/bundle" node-v24.2.0-linux-arm64
cat >"$node_mock_bin/uname" <<'SH'
#!/bin/bash
printf 'aarch64\n'
SH
cat >"$node_mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_TEST_LOG"
SH
chmod +x "$node_mock_bin/uname" "$node_mock_bin/mise"
MISE_TEST_LOG="$node_test/mise.log" \
  HOME="$node_test/home" \
  PATH="$node_mock_bin:$PATH" \
  OMARCHY_SETUP_CONTEXT=provision-owner \
  OMARCHY_NODE_PACKAGE_DIR="$node_test/packages" \
  bash -e -c 'source "$1"' bash "$ROOT/install/user/mise-work.sh"
[[ -x $node_test/home/.local/share/mise/installs/node/24.2.0/bin/node ]] ||
  fail "owner finalization extracts the bundled ARM64 Node.js runtime"
grep -Fx 'use -g node@24.2.0' "$node_test/mise.log" >/dev/null ||
  fail "owner finalization activates the bundled ARM64 Node.js version"
pass "owner finalization consumes the offline ARM64 Node.js bundle"

catalog_source="$test_tmp/catalog.img"
catalog_archive="$catalog_source.xz"
catalog_json="$test_tmp/os-list.json"
dd if=/dev/zero of="$catalog_source" bs=4096 count=1 2>/dev/null
xz --stdout "$catalog_source" >"$catalog_archive"
"$ROOT/image/generate-imager-catalog.sh" "$catalog_archive" \
  https://example.invalid/omarchy-4-pi.img.xz "$catalog_json"
python3 - "$catalog_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    catalog = json.load(stream)

entry = catalog["os_list"][0]
assert entry["devices"] == ["pi4", "pi4-64bit"]
assert entry["architecture"] == "armv8"
assert entry["init_format"] == "rpi-preseed"
assert entry["extract_size"] == 4096
assert len(entry["extract_sha256"]) == 64
assert len(entry["image_download_sha256"]) == 64
PY
pass "Raspberry Pi Imager catalog records image sizes, hashes, and Pi 4 compatibility"

local_catalog_dir="$test_tmp/local catalog"
local_catalog_archive="$local_catalog_dir/Omarchy 4 Pi.img.xz"
local_catalog_manifest="$local_catalog_dir/Omarchy 4 Pi.imager.json"
mkdir -p "$local_catalog_dir"
cp "$catalog_archive" "$local_catalog_archive"
"$ROOT/image/generate-local-imager-manifest.sh" \
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

grep -F 'python3 -m http.server' "$ROOT/image/open-in-rpi-imager-macos.sh" >/dev/null ||
  fail "macOS Imager launcher provides a local HTTP fallback for Imager 2.0"
grep -F -- '--repo "$base_url/$manifest_name"' "$ROOT/image/open-in-rpi-imager-macos.sh" >/dev/null ||
  fail "macOS Imager launcher opens its loopback catalog"
grep -F -- '--bind 127.0.0.1' "$ROOT/image/open-in-rpi-imager-macos.sh" >/dev/null ||
  fail "macOS Imager launcher never exposes the local image server to the LAN"
grep -F '2.0.11 or newer is required for rpi-preseed' "$ROOT/image/open-in-rpi-imager-macos.sh" >/dev/null ||
  fail "macOS Imager launcher rejects versions that prune rpi-preseed catalogs"
pass "macOS Imager launcher enforces rpi-preseed support and a loopback-only catalog"

audit_root="$test_tmp/audit-root"
audit_boot="$test_tmp/audit-boot"
mkdir -p \
  "$audit_boot" \
  "$audit_root/etc/modules-load.d" \
  "$audit_root/etc/pacman.d" \
  "$audit_root/etc/ssh" \
  "$audit_root/etc/systemd/system/multi-user.target.wants" \
  "$audit_root/etc/systemd/system/omarchy-provision-owner.service.d" \
  "$audit_root/etc/skel/.config/hypr" \
  "$audit_root/usr/bin" \
  "$audit_root/usr/local/share/wayland-sessions" \
  "$audit_root/usr/share/omarchy/shell" \
  "$audit_root/usr/share/omarchy/default/hypr" \
  "$audit_root/usr/share/omarchy-rpi4" \
  "$audit_root/usr/share/sddm/themes/omarchy" \
  "$audit_root/opt/omarchy-4-pi/.git" \
  "$audit_root/var/lib/omarchy/provisioning" \
  "$audit_root/var/lib/omarchy/provisioning/packages" \
  "$audit_root/var/lib/pacman/local"

touch \
  "$audit_boot/kernel8.img" \
  "$audit_boot/initramfs-linux.img" \
  "$audit_boot/bcm2711-rpi-4-b.dtb" \
  "$audit_boot/boot.scr" \
  "$audit_boot/start4.elf" \
  "$audit_root/var/lib/omarchy/provisioning/pending" \
  "$audit_root/var/lib/omarchy/provisioning/grow-root-pending" \
  "$audit_root/usr/share/omarchy/shell/shell.qml" \
  "$audit_root/etc/skel/.config/hypr/hyprland.lua" \
  "$audit_root/usr/share/omarchy/default/hypr/raspberry-pi.lua" \
  "$audit_root/usr/share/sddm/themes/omarchy/Main.qml" \
  "$audit_root/opt/omarchy-4-pi/.git/shallow"

cat >"$audit_boot/config.txt" <<'EOF'
dtoverlay=vc4-kms-v3d
max_framebuffers=2
disable_fw_kms_setup=1
EOF
cat >"$audit_root/etc/fstab" <<'EOF'
LABEL=omarchyroot /     ext4 defaults,noatime 0 1
LABEL=OMARCHYBOOT /boot vfat defaults,noatime 0 2
EOF
printf 'vc4\nv3d\n' >"$audit_root/etc/modules-load.d/omarchy-rpi.conf"
printf 'Architecture = aarch64\n' >"$audit_root/etc/pacman.conf"
printf 'Server = https://mirror.archlinuxarm.org/$arch/$repo\n' >"$audit_root/etc/pacman.d/mirrorlist"
printf 'root:x:0:0:root:/root:/bin/bash\nnobody:x:65534:65534:nobody:/:/usr/bin/nologin\n' >"$audit_root/etc/passwd"
printf 'root:!$y$locked:0:0:99999:7:::\n' >"$audit_root/etc/shadow"
: >"$audit_root/etc/machine-id"
cat >"$audit_root/usr/local/share/wayland-sessions/omarchy.desktop" <<'EOF'
[Desktop Entry]
Name=Omarchy
Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop
EOF
ln -s /etc/systemd/system/omarchy-rpi4-grow-root.service \
  "$audit_root/etc/systemd/system/multi-user.target.wants/omarchy-rpi4-grow-root.service"
ln -s /etc/systemd/system/omarchy-provision-owner.service \
  "$audit_root/etc/systemd/system/multi-user.target.wants/omarchy-provision-owner.service"
ln -s /usr/lib/systemd/system/sddm.service \
  "$audit_root/etc/systemd/system/display-manager.service"
ln -s /usr/lib/systemd/system/NetworkManager.service \
  "$audit_root/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
cat >"$audit_root/etc/systemd/system/omarchy-provision-owner.service.d/10-rpi4-grow-root.conf" <<'EOF'
[Unit]
Requires=omarchy-rpi4-grow-root.service
After=omarchy-rpi4-grow-root.service
EOF

# Minimal little-endian ELF64 header with e_machine = EM_AARCH64 (183).
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\267\000' >"$audit_root/usr/bin/Hyprland"
for executable in quickshell foot vcgencmd; do
  cp "$audit_root/usr/bin/Hyprland" "$audit_root/usr/bin/$executable"
done
for executable in omarchy-shell omarchy-rpi4-grow-root omarchy-rpi4-imager-preseed omarchy-provision-owner; do
  printf '#!/bin/bash\n' >"$audit_root/usr/bin/$executable"
done
cat >>"$audit_root/usr/bin/omarchy-provision-owner" <<'EOF'
apply_keyboard "$keyboard"

run_imager_setup() {
  apply_keyboard "$keyboard"
}
EOF
chmod +x "$audit_root/usr/bin/"*

audit_packages=(hyprland quickshell mesa vulkan-broadcom linux-aarch64 raspberrypi-utils sddm networkmanager uwsm chromium foot omarchy omarchy-settings linux-firmware-broadcom)
for package in "${audit_packages[@]}"; do
  package_dir="$audit_root/var/lib/pacman/local/$package-1.0-1"
  mkdir -p "$package_dir"
  cat >"$package_dir/desc" <<EOF
%NAME%
$package

%VERSION%
1.0-1

%ARCH%
aarch64
EOF
done

node_bundle="$audit_root/var/lib/omarchy/provisioning/packages/node-v24.0.0-linux-arm64.tar.gz"
printf 'verified ARM64 Node fixture\n' >"$node_bundle"
node_bundle_sha=$(sha256sum "$node_bundle" | awk '{ print $1 }')

manifest="$audit_root/usr/share/omarchy-rpi4/build-manifest.json"
{
  printf '{\n  "source_dirty": false,\n'
  printf '  "source_commit": "89abcdef0123456789abcdef0123456789abcdef",\n'
  printf '  "omarchy_pkgs_commit": "0123456789abcdef0123456789abcdef01234567",\n'
  printf '  "base_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",\n'
  printf '  "base_signing_key": "68B3537F39A313B3E574D06777193F152BDBE6A6",\n'
  printf '  "node_bundle": {"filename": "node-v24.0.0-linux-arm64.tar.gz", "sha256": "%s"},\n' "$node_bundle_sha"
  printf '  "packages": [\n'
  separator=""
  for package in "${audit_packages[@]}"; do
    printf '%s    {"name": "%s", "version": "1.0-1"}' "$separator" "$package"
    separator=$',\n'
  done
  printf '\n  ]\n}\n'
} >"$manifest"

"$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-ok"
grep -F 'PASS:' "$test_tmp/audit-ok" >/dev/null || fail "image root audit reports its passing invariant count"
pass "image root audit accepts a complete ARM64 Quattro payload"

grow_dependency="$audit_root/etc/systemd/system/omarchy-provision-owner.service.d/10-rpi4-grow-root.conf"
cp "$grow_dependency" "$test_tmp/complete-grow-dependency.conf"
sed -i.bak '/^Requires=omarchy-rpi4-grow-root.service$/d' "$grow_dependency"
if "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-grow-dependency" 2>&1; then
  fail "image root audit rejects fail-open owner provisioning"
fi
grep -F 'owner provisioning requires successful root expansion' "$test_tmp/audit-grow-dependency" >/dev/null ||
  fail "image root audit identifies a missing root-growth requirement"
mv "$test_tmp/complete-grow-dependency.conf" "$grow_dependency"
pass "image root audit rejects fail-open owner provisioning"

printf 'corrupted\n' >>"$node_bundle"
if "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-node" 2>&1; then
  fail "image root audit rejects a corrupted offline Node.js bundle"
fi
grep -F 'ARM64 Node.js bundle matches build provenance' "$test_tmp/audit-node" >/dev/null ||
  fail "image root audit identifies a corrupted offline Node.js bundle"
printf 'verified ARM64 Node fixture\n' >"$node_bundle"
pass "image root audit rejects a corrupted offline Node.js bundle"

cp "$manifest" "$test_tmp/complete-manifest.json"
sed -i.bak '/"name": "omarchy"/d' "$manifest"
if "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-inventory" 2>&1; then
  fail "image root audit rejects an incomplete package inventory"
fi
grep -F 'build manifest records every installed package and exact version' "$test_tmp/audit-inventory" >/dev/null ||
  fail "image root audit identifies an incomplete package inventory"
mv "$test_tmp/complete-manifest.json" "$manifest"
pass "image root audit rejects an incomplete package inventory"

cp "$manifest" "$test_tmp/complete-manifest.json"
sed -i.bak 's/"name": "omarchy", "version": "1.0-1"/"name": "omarchy", "version": "9.9-9"/' "$manifest"
if "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-version" 2>&1; then
  fail "image root audit rejects an incorrect package version"
fi
grep -F 'build manifest records every installed package and exact version' "$test_tmp/audit-version" >/dev/null ||
  fail "image root audit identifies an incorrect package version"
mv "$test_tmp/complete-manifest.json" "$manifest"
pass "image root audit rejects an incorrect package version"

printf '\076\000' | dd of="$audit_root/usr/bin/quickshell" bs=1 seek=18 conv=notrunc 2>/dev/null
if "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-bad" 2>&1; then
  fail "image root audit rejects an x86 Quickshell executable"
fi
grep -F 'Quickshell executable is AArch64' "$test_tmp/audit-bad" >/dev/null ||
  fail "image root audit identifies the incompatible executable"
pass "image root audit rejects an incompatible desktop executable"

cp "$audit_root/usr/bin/Hyprland" "$audit_root/usr/bin/quickshell"
package_dir="$audit_root/var/lib/pacman/local/linux-firmware-nvidia-1.0-1"
mkdir -p "$package_dir"
cat >"$package_dir/desc" <<'EOF'
%NAME%
linux-firmware-nvidia

%VERSION%
1.0-1

%ARCH%
any
EOF
if "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-firmware" 2>&1; then
  fail "image root audit rejects PC-only firmware"
fi
grep -F 'non-Pi firmware package linux-firmware-nvidia is absent' "$test_tmp/audit-firmware" >/dev/null ||
  fail "image root audit identifies the PC-only firmware package"
pass "image root audit rejects PC-only firmware bloat"

rm -rf "$package_dir"
touch "$audit_root/etc/._shadow"
if "$ROOT/image/audit-rpi4-rootfs.sh" "$audit_root" "$audit_boot" >"$test_tmp/audit-appledouble" 2>&1; then
  fail "image root audit rejects macOS metadata sidecars"
fi
grep -F 'macOS metadata sidecars are absent' "$test_tmp/audit-appledouble" >/dev/null ||
  fail "image root audit identifies macOS metadata sidecars"
pass "image root audit rejects macOS metadata sidecars"
