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
bash -n "$ROOT/image/generate-imager-catalog.sh"
bash -n "$ROOT/image/prepare-release-assets.sh"
pass "Raspberry Pi install, image, and update entrypoints parse"

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
grep -F '/var/lib/omarchy/provisioning/grow-root-pending' \
  "$ROOT/bin/omarchy-rpi4-grow-root" >/dev/null || fail "root growth is guarded by a one-shot marker"
pass "image mode arms ordered first-boot storage growth and owner provisioning"

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
assert entry["devices"] == ["pi4"]
assert entry["architecture"] == "armv8"
assert entry["init_format"] == "none"
assert entry["extract_size"] == 4096
assert len(entry["extract_sha256"]) == 64
assert len(entry["image_download_sha256"]) == 64
PY
pass "Raspberry Pi Imager catalog records image sizes, hashes, and Pi 4 compatibility"
