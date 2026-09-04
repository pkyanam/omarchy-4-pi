#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# Execute the actual orchestration in a child shell, as --imager-attempt does.
# No real account, hostname, or systemd operations are permitted in this fixture.
for function in configure_hostname run_provisioning run_imager_setup; do
  sed -n "/^$function() {$/,/^}$/p" "$ROOT/bin/omarchy-provision-owner" >>"$test_tmp/functions"
done
cat >"$test_tmp/attempt" <<'BASH'
set -euo pipefail
source "$fixture/functions"
hostname=omarchy-pi
username=piowner
keyboard=us
LOG_FILE="$fixture/log"
STATE_FILE="$fixture/state"
PROVISIONING_DIR="$fixture"
FINALIZE_WARNING_FLAG="$fixture/warning"
SHOW_CURSOR=""
hostnamectl() {
  case "$1" in
    set-hostname)
      [[ $scenario != failure ]] || return 1
      printf '%s\n' "$2" >"$fixture/hostname"
      ;;
    --static) cat "$fixture/hostname" ;;
    --transient)
      if [[ $scenario == mismatch ]]; then echo omarchy; else cat "$fixture/hostname"; fi
      ;;
  esac
}
log_step() { :; }
create_user() { echo user >>"$fixture/events"; }
install_authorized_keys() { :; }
configure_imager_network() { :; }
configure_imager_ssh() {
  [[ $(cat "$fixture/hostname") == omarchy-pi ]]
  echo ssh >>"$fixture/events"
}
configure_login() { :; }
configure_timezone() { :; }
finalize_user() { :; }
limine_entries_stale() { return 1; }
cleanup_oem_state() { echo cleanup >>"$fixture/events"; }
apply_keyboard() { :; }
set_now() { NOW=1; }
render_setup_static() { :; }
render_setup_dynamic() { :; }
sleep() { command sleep 0.01; }
run_imager_setup
BASH
export fixture="$test_tmp"
for scenario in success failure mismatch; do
  export scenario
  : >"$test_tmp/events"
  if bash "$test_tmp/attempt"; then
    [[ $scenario == success ]] || fail "hostname $scenario must fail unattended setup"
    [[ $(<"$test_tmp/state") == done ]] || fail "successful owner setup completes"
    [[ $(<"$test_tmp/hostname") == omarchy-pi ]] || fail "chosen hostname persists"
    grep -Fx ssh "$test_tmp/events" >/dev/null || fail "SSH starts after the chosen hostname"
  else
    [[ $scenario != success ]] || fail "valid hostname succeeds"
    [[ ! -s $test_tmp/events ]] || fail "hostname failure stops account creation and cleanup"
    [[ $(<"$test_tmp/state") != done ]] || fail "hostname failure cannot mark setup complete"
  fi
done
grep -F 'if "$0" --imager-attempt; then' "$ROOT/bin/omarchy-provision-owner" >/dev/null || fail "unattended setup uses a child process"
grep -Fx 'After=omarchy-provision-owner.service' "$ROOT/install/provisioning/omarchy-avahi-rpi4.conf" >/dev/null || fail "mDNS waits for provisioning"
pass "owner hostname precedes SSH; set/readback failures stop unattended setup"
