#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

make_root() {
  local root="$1"
  mkdir -p "$root/boot" "$root/usr/share/zoneinfo/America"
  : >"$root/usr/share/zoneinfo/UTC"
  : >"$root/usr/share/zoneinfo/America/New_York"
}

valid_root="$test_tmp/valid"
make_root "$valid_root"
ssh-keygen -q -t ed25519 -N '' -f "$test_tmp/imager-key" </dev/null
cat >"$valid_root/boot/rpi-preseed.toml" <<'TOML'
config_version = "1.0"

[system]
hostname = "quattro-pi"

[user]
name = "piowner"
password = "$y$j9T$abcdefghijklmnop$abcdefghijklmnopqrstuvwxzy0123456789ABCDEFGHIJK"
password_encrypted = true
passwordless_sudo = true
groups = ["sudo"]

[ssh]
enabled = true
password_authentication = false
authorized_keys = ["IMAGER_TEST_PUBLIC_KEY"]

[wlan]
ssid = "Tiny Board Wi-Fi"
password = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
password_encrypted = true
hidden = false
country = "US"

[locale]
keymap = "us"
timezone = "America/New_York"
TOML
public_key=$(<"$test_tmp/imager-key.pub")
sed -i.bak "s|IMAGER_TEST_PUBLIC_KEY|$public_key|" "$valid_root/boot/rpi-preseed.toml"

output=$(OMARCHY_PRESEED_ROOT="$valid_root" \
  "$ROOT/bin/omarchy-rpi4-imager-preseed" stage 2>&1) ||
  fail "valid Raspberry Pi Imager settings stage successfully: $output"
[[ -z $output ]] || fail "successful preseed staging does not print secrets"
state="$valid_root/var/lib/omarchy/provisioning/imager"
[[ -f $state/ready ]] || fail "valid Imager settings arm unattended owner setup"
[[ $(<"$state/username") == piowner ]] || fail "Imager username is staged"
[[ $(<"$state/hostname") == quattro-pi ]] || fail "Imager hostname is staged"
[[ $(<"$state/timezone") == America/New_York ]] || fail "Imager timezone is staged"
grep -Fx "$public_key" "$state/authorized_keys" >/dev/null ||
  fail "validated SSH key is staged for the owner"
grep -F 'ssid=84;105;110;121;32;66;111;97;114;100;32;87;105;45;70;105;' \
  "$valid_root/etc/NetworkManager/system-connections/omarchy-imager.nmconnection" >/dev/null ||
  fail "Wi-Fi SSID is encoded safely for NetworkManager"
grep -Fx 'WIRELESS_REGDOM="US"' "$valid_root/etc/conf.d/wireless-regdom" >/dev/null ||
  fail "Wi-Fi regulatory domain is staged"
python3 - "$state/password-hash" \
  "$valid_root/etc/NetworkManager/system-connections/omarchy-imager.nmconnection" <<'PY'
import os
import stat
import sys

for filename in sys.argv[1:]:
    assert stat.S_IMODE(os.stat(filename).st_mode) == 0o600
PY
pass "Imager settings stage hashed credentials and Wi-Fi with private permissions"

plaintext_root="$test_tmp/plaintext"
make_root "$plaintext_root"
cat >"$plaintext_root/boot/rpi-preseed.toml" <<'TOML'
config_version = "1.0"
[user]
name = "piowner"
password = "please-do-not-put-this-on-fat"
password_encrypted = false
TOML
if OMARCHY_PRESEED_ROOT="$plaintext_root" \
  "$ROOT/bin/omarchy-rpi4-imager-preseed" stage >"$test_tmp/plain.out" 2>"$test_tmp/plain.err"; then
  fail "plaintext owner credentials on the FAT partition are rejected"
fi
[[ ! -e $plaintext_root/var/lib/omarchy/provisioning/imager/ready ]] ||
  fail "rejected plaintext credentials do not arm unattended setup"
grep -F 'plaintext owner passwords are refused' "$test_tmp/plain.err" >/dev/null ||
  fail "plaintext rejection explains the secure Imager path"
pass "preseed refuses plaintext owner passwords"

partial_root="$test_tmp/partial"
make_root "$partial_root"
cat >"$partial_root/boot/rpi-preseed.toml" <<'TOML'
config_version = "1.0"
[system]
hostname = "still-interactive"
TOML
partial_status=0
OMARCHY_PRESEED_ROOT="$partial_root" \
  "$ROOT/bin/omarchy-rpi4-imager-preseed" stage || partial_status=$?
[[ $partial_status == 3 ]] || fail "partial settings preserve interactive setup"
[[ ! -e $partial_root/var/lib/omarchy/provisioning/imager/ready ]] ||
  fail "partial settings never bypass owner setup"
pass "partial Imager settings preserve interactive onboarding"

# Execute the unattended handoff itself under nounset. A source-only grep once
# missed a zero-argument apply_keyboard call because another setup path happened
# to contain the correct text; this fixture fails on the actual argument flow.
handoff="$test_tmp/handoff"
mkdir -p "$handoff"
sed -n '/^run_imager_setup() {$/,/^}$/p' "$ROOT/bin/omarchy-provision-owner" >"$handoff/function.sh"
(
  set -euo pipefail
  LOG_FILE="$handoff/provision.log"
  FINALIZE_WARNING_FLAG="$handoff/finalize-warning"
  STATE_FILE="$handoff/state"
  SHOW_CURSOR=""
  keyboard=us
  NOW=0
  SETUP_T0=0
  SETUP_PHASE_T0=0

  apply_keyboard() {
    [[ $# == 1 && $1 == us ]]
    printf '%s\n' "$1" >"$handoff/keymap"
  }
  run_provisioning() { printf 'provisioned\n'; }
  set_now() { NOW=1; }
  render_setup_static() { :; }
  render_setup_dynamic() { :; }
  sleep() { :; }

  source "$handoff/function.sh"
  run_imager_setup
)
[[ $(<"$handoff/keymap") == us ]] || fail "unattended setup passes the staged keymap at runtime"
[[ $(<"$handoff/state") == done ]] || fail "unattended setup reaches its completed state"
grep -Fx provisioned "$handoff/provision.log" >/dev/null ||
  fail "unattended setup runs owner provisioning"
pass "unattended Imager handoff passes its staged keymap at runtime"
