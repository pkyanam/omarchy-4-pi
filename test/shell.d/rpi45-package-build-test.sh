#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command bsdtar
require_command python3
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/recipes/omarchy-keyring" "$test_tmp/build" "$test_tmp/cache/packages" "$test_tmp/output"
export PATH="$test_tmp/bin:$PATH" TEST_TMP=$test_tmp TEST_CALLS="$test_tmp/calls"
export OMARCHY_PI_BUILD_CACHE="$test_tmp/cache" OMARCHY_PI_MAKEPKG_CONF="$test_tmp/makepkg.conf"
# The target is Linux; adapt only macOS sed's in-place option at the test
# boundary, without rewriting the production Linux command.
if [[ $(uname -s) == "Darwin" ]]; then
  cat >"$test_tmp/bin/sed" <<'SH'
#!/bin/bash
if [[ ${1:-} == -i ]]; then
  shift
  exec /usr/bin/sed -i '' "$@"
else
  exec /usr/bin/sed "$@"
fi
SH
  chmod +x "$test_tmp/bin/sed"
fi
printf 'pkgname=omarchy-keyring\npkgver=20251027\npkgrel=1\n' >"$test_tmp/recipes/omarchy-keyring/PKGBUILD"
: >"$OMARCHY_PI_MAKEPKG_CONF"
cat >"$test_tmp/bin/makepkg" <<'SH'
#!/bin/bash
if [[ " $* " == *" --packagelist "* ]]; then
  printf '%s/omarchy-keyring.pkg.tar.gz\n' "$OMARCHY_PI_BUILD_CACHE/packages"
  exit 0
fi
printf '%s\n' "$@" >"$TEST_CALLS"
printf 'pkgname = omarchy-keyring\npkgver = 20251027-1\narch = any\n' >"$TEST_TMP/.PKGINFO"
bsdtar -czf "$OMARCHY_PI_BUILD_CACHE/packages/omarchy-keyring.pkg.tar.gz" -C "$TEST_TMP" .PKGINFO
SH
chmod +x "$test_tmp/bin/makepkg"
# Source only the real builder's functions; this invokes no build orchestration.
OMARCHY_PACKAGE_OUTPUT="$test_tmp/output" bash -c '
  source "$OMARCHY_PATH/build-packages-rpi4.sh"
  build_root="$TEST_TMP/build" source_tree="$TEST_TMP/source" source_cache="$TEST_TMP/cache/sources"
  build_package omarchy-keyring "$TEST_TMP/recipes"
'
[[ -f $test_tmp/output/omarchy-keyring.pkg.tar.gz ]] || fail "builder did not persist the artifact from configured PKGDEST"
grep -Fx -- '--config' "$TEST_CALLS" >/dev/null || fail "builder did not use bounded makepkg config"
grep -Fx -- "$OMARCHY_PI_MAKEPKG_CONF" "$TEST_CALLS" >/dev/null || fail "wrong bounded makepkg config"
if grep -E -- '^--skip(integ|checksums|pgpcheck)$' "$TEST_CALLS"; then fail "external source integrity was disabled"; fi
[[ -f $OMARCHY_PI_BUILD_CACHE/packages/omarchy-keyring.pkg.tar.gz ]] || fail "builder moved caller PKGDEST archives"
pass "builder passes the bounded config, retains source integrity flags and persists helper PKGDEST artifacts"

# Exercise the actual Pi settings wrapper on a package-shaped payload. This
# catches vendor zram and generic boot leakage without any compiler or install.
cat >"$test_tmp/settings.PKGBUILD" <<'RECIPE'
pkgver=4.5.0
pkgrel=3
backup=('etc/mkinitcpio.conf.d/00-omarchy-hooks.conf' 'etc/sysctl.d/99-omarchy-sysctl.conf')
package() {
  mkdir -p "$pkgdir/etc/mkinitcpio.conf.d" "$pkgdir/etc/limine-entry-tool.d" \
    "$pkgdir/etc/sysctl.d" "$pkgdir/usr/lib/systemd/zram-generator.conf.d" \
    "$pkgdir/usr/bin"
  echo 'HOOKS=(encrypt btrfs-overlayfs)' >"$pkgdir/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf"
  echo '[zram0]' >"$pkgdir/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf"
  printf 'net.ipv4.tcp_mtu_probing=1\nvm.swappiness=150\nvm.dirty_bytes=268435456\n' >"$pkgdir/etc/sysctl.d/99-omarchy-sysctl.conf"
  touch "$pkgdir/usr/bin/omarchy-security-functions"
  provides=('omarchy-security-functions')
}
RECIPE
bash -c '
  source "$OMARCHY_PATH/build-packages-rpi4.sh"
  adapt_recipe omarchy-settings "$TEST_TMP/settings.PKGBUILD"
  source "$TEST_TMP/settings.PKGBUILD"
  pkgdir="$TEST_TMP/settings"
  package
  [[ ! -d $pkgdir/etc/mkinitcpio.conf.d && ! -e $pkgdir/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf ]]
  [[ -f $pkgdir/usr/bin/omarchy-security-functions && ${provides[0]} == omarchy-security-functions ]]
  [[ ${backup[*]} == etc/sysctl.d/99-omarchy-sysctl.conf ]]
  grep -qx "net.ipv4.tcp_mtu_probing=1" "$pkgdir/etc/sysctl.d/99-omarchy-sysctl.conf"
  ! grep -q "^vm[.]" "$pkgdir/etc/sysctl.d/99-omarchy-sysctl.conf"
  grep -qx AbortOnFail "$pkgdir/usr/share/libalpm/hooks/00-omarchy-rpi4-core-guard.hook"
' || fail "Pi settings wrapper leaked boot/memory policy or lost security ownership"
pass "Pi settings filter removes generic boot/vendor memory settings, retains networking/security and protects local core operations"

# Run the real boot-check function against tiny files at a rewritten fixed
# root. OS tools are external boundaries; none can reach the host boot tree.
mkdir -p "$test_tmp/boot/dtbs/broadcom" "$test_tmp/modules/test-kernel"
for asset in kernel8.img Image boot.scr boot.txt start4.elf fixup4.dat config.txt bcm2711-rpi-4-b.dtb dtbs/broadcom/bcm2711-rpi-4-b.dtb initramfs-linux.img; do
  printf fixture >"$test_tmp/boot/$asset"
done
printf fixture >"$test_tmp/modules/test-kernel/modules.builtin"
python3 - "$ROOT/bin/omarchy-update-boot" "$test_tmp" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text();p=Path(sys.argv[2])
s=s[s.index('pi_boot_check() {'):s.index('\nif [[ ${1:-} == "--pi4-check"')]
s=s.replace('local boot=/boot',f'local boot={p}/boot').replace('(( EUID == 0 ))','true').replace('/usr/lib/modules',f'{p}/modules')
(p/'boot-check').write_text('set -e\n'+s+'\npi_boot_check\n')
PY
cat >"$test_tmp/bin/findmnt" <<'SH'
#!/bin/bash
echo "${TEST_BOOT_FS:-vfat}"
SH
cat >"$test_tmp/bin/df" <<'SH'
#!/bin/bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 524288 100000 %s 20%% /boot\n' "${TEST_BOOT_FREE:-400000}"
SH
cat >"$test_tmp/bin/pacman" <<'SH'
#!/bin/bash
printf '%s/modules/test-kernel/modules.builtin\n' "$TEST_TMP"
SH
cat >"$test_tmp/bin/mkinitcpio" <<'SH'
#!/bin/bash
echo mkinitcpio >>"$TEST_CALLS"
exit "${TEST_MKINITCPIO_STATUS:-0}"
SH
cat >"$test_tmp/bin/lsinitcpio" <<'SH'
#!/bin/bash
printf 'usr/lib/modules/%s/kernel/driver.ko\n' "${TEST_INITRAMFS_KERNEL:-test-kernel}"
SH
chmod +x "$test_tmp/bin/"*
bash "$test_tmp/boot-check" >"$test_tmp/boot-check.log" 2>&1 || fail "healthy static boot fixture failed" "$(cat "$test_tmp/boot-check.log")"
reject_boot() {
  if env "$@" bash "$test_tmp/boot-check" >"$test_tmp/boot-check.log" 2>&1; then fail "unsafe boot fixture unexpectedly passed" "$*"; fi
}
reject_boot TEST_MKINITCPIO_STATUS=1
reject_boot TEST_INITRAMFS_KERNEL=stale-kernel
reject_boot TEST_BOOT_FS=ext4
reject_boot TEST_BOOT_FREE=1024
rm "$test_tmp/boot/Image"
reject_boot
pass "Pi boot verification rejects initramfs failure, wrong kernel, unmounted/full boot and missing Linux Image"
