#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

root="$test_tmp/root"
mkdir -p "$root/etc/skel/.config/hypr" "$root/usr/bin"
printf '%s\n' '-- owner config fixture' >"$root/etc/skel/.config/hypr/hyprland.lua"
printf '#!/bin/bash\n' >"$root/usr/bin/Hyprland"
chmod +x "$root/usr/bin/Hyprland"

mock_chroot="$test_tmp/chroot"
cat >"$mock_chroot" <<'MOCK'
#!/bin/bash
set -euo pipefail
root=$1
shift
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ $* == *'/usr/bin/Hyprland --version'* ]]; then
  printf 'Hyprland 0.56.1 test build\n'
elif [[ $* == *'/usr/bin/Hyprland --verify-config'* ]]; then
  [[ ${OMARCHY_TEST_VERIFY_FAIL:-0} == 0 ]] || exit 9
  printf 'debug fixture\nconfig ok\n'
elif [[ $1 == chown ]]; then
  :
else
  printf 'unexpected chroot command below %s: %s\n' "$root" "$*" >&2
  exit 64
fi
MOCK
chmod +x "$mock_chroot"

calls="$test_tmp/calls"
: >"$calls"
OMARCHY_CHROOT_COMMAND="$mock_chroot" OMARCHY_TEST_CALLS="$calls" \
  "$ROOT/image/verify-rpi4-hyprland.sh" "$root" image-user >"$test_tmp/verify.out"
receipt="$root/usr/share/omarchy-rpi4/hyprland-config-verified"
grep -Fx 'config ok' "$test_tmp/verify.out" >/dev/null || fail "Hyprland verifier preserves the parser result"
grep -Fx 'version=Hyprland 0.56.1 test build' "$receipt" >/dev/null ||
  fail "Hyprland verifier records the image binary version"
grep -F 'OMARCHY_RPI_MODEL_PATH=/tmp/omarchy-rpi4-hyprland-verify/pi-model' "$calls" >/dev/null ||
  fail "Hyprland verifier activates the Pi compatibility profile"
[[ ! -e $root/tmp/omarchy-rpi4-hyprland-verify ]] || fail "Hyprland verifier removes its temporary profile"
pass "image factory verifies the ARM64 Hyprland Pi configuration"

rm -f "$receipt"
: >"$calls"
status=0
OMARCHY_CHROOT_COMMAND="$mock_chroot" OMARCHY_TEST_CALLS="$calls" OMARCHY_TEST_VERIFY_FAIL=1 \
  "$ROOT/image/verify-rpi4-hyprland.sh" "$root" image-user >"$test_tmp/fail.out" 2>&1 || status=$?
[[ $status == 9 ]] || fail "Hyprland parser failure is propagated"
[[ ! -e $receipt ]] || fail "failed Hyprland verification writes no receipt"
[[ ! -e $root/tmp/omarchy-rpi4-hyprland-verify ]] || fail "failed Hyprland verification removes temporary state"
pass "image factory refuses a broken Hyprland Pi configuration"
