#!/bin/bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mock_bin=$test_tmp/bin
omarchy=$test_tmp/omarchy
mkdir -p "$mock_bin" "$omarchy/bin" "$omarchy/install/user/first-run" "$omarchy/default/agents/skills/omarchy" "$omarchy/migrations"
ln -s "$ROOT/bin/omarchy-done" "$omarchy/bin/omarchy-done"

for command in xdg-user-dirs-update xdg-settings xdg-mime omarchy-refresh-applications omarchy-notification-wait omarchy-lifecycle-dispatch; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CALLS"
SH
chmod +x "$mock_bin"/*
export PATH="$mock_bin:$PATH"
export TEST_CALLS=$test_tmp/calls
export TEST_FAILURE=$test_tmp/fail
: >"$TEST_CALLS"

cat >"$omarchy/install/user/all.sh" <<'SH'
run_logged "$OMARCHY_INSTALL/user/required.sh"
SH
cat >"$omarchy/install/user/required.sh" <<'SH'
echo required >>"$TEST_CALLS"
echo "context $OMARCHY_SETUP_CONTEXT" >>"$TEST_CALLS"
[[ ! -f $TEST_FAILURE ]] || exit 23
SH
: >"$omarchy/migrations/123.sh"

run_user() {
  HOME="$test_tmp/user-home" PATH="$omarchy/bin:$PATH" OMARCHY_PATH="$omarchy" OMARCHY_INSTALL="$omarchy/install" OMARCHY_SETUP_CONTEXT="${TEST_CONTEXT:-runtime}" \
    bash "$ROOT/bin/omarchy-provision-user" "$@" >"$test_tmp/user.log" 2>&1
}

# A failed forced/first-install run must retire an old completion marker and
# leave migrations unmarked. The real finalizer's next invocation must retry.
if (( EUID != 0 )); then
  mkdir -p "$test_tmp/user-home/.local/state/omarchy/done"
  touch "$TEST_FAILURE" "$test_tmp/user-home/.local/state/omarchy/done/finalize-user"
  status=0
  run_user --first-install || status=$?
  (( status == 23 )) || fail "required setup failure reaches the finalizer's caller" "$(cat "$test_tmp/user.log")"
  [[ ! -e $test_tmp/user-home/.local/state/omarchy/done/finalize-user ]] || fail "failed forced finalization stays retryable"
  [[ ! -e $test_tmp/user-home/.local/state/omarchy/migrations/123.sh ]] || fail "failed first-install setup marks no migration complete"
  rm "$TEST_FAILURE"
  run_user --first-install || fail "finalization retries successfully" "$(cat "$test_tmp/user.log")"
  [[ -f $test_tmp/user-home/.local/state/omarchy/done/finalize-user && -f $test_tmp/user-home/.local/state/omarchy/migrations/123.sh ]] || fail "successful retry completes user setup and first-install migrations"
  run_user || fail "completed finalization is idempotent"
  (( $(grep -c '^required$' "$TEST_CALLS") == 2 )) || fail "completed user setup does not rerun required leaves"
  grep -Fxq 'context iso-chroot' "$TEST_CALLS" || fail "first-install finalization preserves the ISO context for setup leaves"
  TEST_CONTEXT=provision-owner run_user --first-install || fail "owner finalization succeeds with its first-install context"
  grep -Fxq 'context provision-owner' "$TEST_CALLS" || fail "owner finalization preserves its context for first-install Pi defaults"
  pass "required user setup failure invalidates stale success and retries before marking migrations"
else
  skip "real user finalization requires a non-root fixture runner"
fi

for leaf in enable-user-units gnome-theme gtk-primary-paste audio-tuning superwhisper welcome git wifi; do
  : >"$omarchy/install/user/first-run/$leaf.sh"
done
cat >"$mock_bin/omarchy-provision-user" <<'SH'
#!/bin/bash
echo finalize >>"$TEST_CALLS"
[[ ! -f $TEST_FAILURE ]] || exit 23
omarchy-done mark finalize-user
SH
chmod +x "$mock_bin/omarchy-provision-user"
first_home=$test_tmp/first-home
mkdir -p "$first_home/.local/state/omarchy/done"
# Recover the stale first-run success the baseline F4 bug could have left.
touch "$first_home/.local/state/omarchy/done/first-run-user" "$TEST_FAILURE"
run_first_login() {
  HOME="$first_home" OMARCHY_PATH="$omarchy" PATH="$omarchy/bin:$PATH" \
    bash "$ROOT/bin/omarchy-provision-first-run" >"$test_tmp/first-run.out" 2>&1
}
if run_first_login; then fail "first login reports failed finalization"; fi
[[ ! -e $first_home/.local/state/omarchy/done/first-run-user ]] || fail "failed finalization cannot complete first run"
grep -Fq 'Failed: finalize user runtime (exit code: 23)' "$first_home/.local/state/omarchy/first-run.log" || fail "first-run persists the finalizer failure"
grep -Fq 'Omarchy setup is incomplete' "$TEST_CALLS" || fail "first login displays incomplete setup"
rm "$TEST_FAILURE"
run_first_login || fail "second login retries and succeeds" "$(cat "$test_tmp/first-run.out")"
[[ -f $first_home/.local/state/omarchy/done/first-run-user ]] || fail "successful retry completes first run"
calls_before=$(grep -c '^finalize$' "$TEST_CALLS")
run_first_login || fail "completed first run is idempotent"
(( $(grep -c '^finalize$' "$TEST_CALLS") == calls_before )) || fail "completed first run runs no finalizer"
pass "first login exposes and retries finalizer failure, including a stale first-run marker"

# Execute the real owner workers in independent strict shells, as the service
# does. Only hardware/account/session boundaries are stubbed; all paths land
# in the fixture. No host account, hostname, key, boot or systemd writes occur.
for function in run_provisioning run_imager_setup run_setup platform_ready configure_hostname create_user configure_password install_authorized_keys cleanup_oem_state; do
  sed -n "/^$function() {$/,/^}$/p" "$ROOT/bin/omarchy-provision-owner"
done | sed -e "s|/etc/|$test_tmp/root/etc/|g" -e "s|/home/|$test_tmp/root/home/|g" \
  -e "s|/opt/|$test_tmp/root/opt/|g" -e "s|/boot/|$test_tmp/root/boot/|g" \
  -e "s|/var/lib/|$test_tmp/root/var/lib/|g" >"$test_tmp/owner-functions"
mkdir -p "$omarchy/install/helpers"
echo 'BROWSER_POLICY_MANAGED_DIRS=()' >"$omarchy/install/helpers/browser-policy.sh"
for command in omarchy-provision-hardware omarchy-lifecycle-dispatch; do
  cat >"$omarchy/bin/$command" <<'SH'
#!/bin/bash
[[ ! -e $TEST_HARDWARE_FAILURE ]] || exit 75
SH
done
chmod +x "$omarchy/bin/omarchy-provision-hardware" "$omarchy/bin/omarchy-lifecycle-dispatch"

cat >"$test_tmp/owner-attempt" <<'SH'
set -euo pipefail
source "$TEST_FIXTURE/owner-functions"
PROVISIONING_DIR=$TEST_FIXTURE/root/var/lib/omarchy/provisioning
IMAGER_STATE_DIR=$PROVISIONING_DIR/imager
REKEY_STATE=$PROVISIONING_DIR/luks-rekey.state
FINALIZE_WARNING_FLAG=$PROVISIONING_DIR/finalize-failed
STATE_FILE=$TEST_FIXTURE/state
LOG_FILE=$TEST_FIXTURE/owner.log
username=piowner
hostname=omarchy-pi
timezone=UTC
keyboard=us
password=fixture-hash
password_encrypted=true
passwordless_sudo=false
SHOW_CURSOR=""
user_groups() { echo wheel; }
getent() { [[ -f $TEST_FIXTURE/account ]]; }
useradd() { touch "$TEST_FIXTURE/account"; echo useradd >>"$TEST_CALLS"; }
usermod() { echo usermod >>"$TEST_CALLS"; }
chpasswd() { cat >/dev/null; echo "chpasswd $*" >>"$TEST_CALLS"; }
chown() { printf 'chown %s\n' "$*" >>"$TEST_CALLS"; }
runuser() {
  [[ $1 == "-u" && $2 == "piowner" && $3 == "--" ]] || return 1
  echo "keys-as-owner" >>"$TEST_CALLS"
  shift 3
  "$@"
}
systemctl() { :; }
rm() {
  if [[ -e $TEST_CLEANUP_FAILURE && $* == *"/boot/rpi-preseed.toml"* ]]; then return 24; fi
  command rm "$@"
}
hostnamectl() {
  case $1 in
    set-hostname) echo "$2" >"$TEST_FIXTURE/hostname" ;;
    --static|--transient) cat "$TEST_FIXTURE/hostname" ;;
  esac
}
log_step() { echo "$*" >>"$LOG_FILE"; }
configure_imager_network() { :; }
configure_imager_ssh() { [[ $(<"$TEST_FIXTURE/hostname") == "$hostname" ]]; }
configure_timezone() { :; }
configure_login() { touch "$TEST_FIXTURE/login-ready"; }
finalize_user() { [[ ! -f $TEST_FAILURE ]] || return 23; }
luks_rekey_pending() { return 1; }
luks_rekey() { :; }
rekey_luks() { :; }
luks_staged_unlock_remains() { return 1; }
limine_entries_stale() { return 1; }
apply_keyboard() { [[ $1 == us ]]; }
keyboard_form() { :; }
user_form() { :; }
confirm_form() { return 0; }
rekey_accepts_password() { return 0; }
set_now() { NOW=1; }
render_setup_static() { :; }
render_setup_dynamic() { :; }
render_setup_finish() { :; }
clear_logo() { :; }
say() { :; }
sleep() { command sleep 0.01; }
"$1"
SH
export TEST_FIXTURE=$test_tmp
export TEST_HARDWARE_FAILURE=$test_tmp/hardware-fail
export TEST_CLEANUP_FAILURE=$test_tmp/cleanup-fail

for worker in run_imager_setup run_setup; do
  rm -rf "$test_tmp/root" "$test_tmp/account" "$test_tmp/login-ready"
  provisioning=$test_tmp/root/var/lib/omarchy/provisioning
  mkdir -p "$provisioning/imager" "$provisioning/packages" "$test_tmp/root/etc/sudoers.d" \
    "$test_tmp/root/opt/omarchy-4-pi/.git" "$test_tmp/root/home/piowner/.ssh"
  touch "$provisioning/pending" "$provisioning/groups"
  touch "$provisioning/luks-rekey.state" "$TEST_FAILURE" "$TEST_HARDWARE_FAILURE"
  printf 'existing-key' >"$test_tmp/root/home/piowner/.ssh/authorized_keys"
  printf 'imager-key\n' >"$provisioning/authorized_keys"
  : >"$TEST_CALLS"
  if OMARCHY_PATH="$omarchy" bash "$test_tmp/owner-attempt" "$worker"; then fail "$worker waits for deferred hardware setup"; fi
  [[ ! -e $test_tmp/account && -f $provisioning/pending ]] || fail "hardware failure cannot start or complete owner setup"
  rm "$TEST_HARDWARE_FAILURE"
  status=0
  OMARCHY_PATH="$omarchy" bash "$test_tmp/owner-attempt" "$worker" || status=$?
  (( status == 23 )) || fail "$worker propagates finalizer failure" "status=$status; $(cat "$test_tmp/owner.log")"
  [[ -f $provisioning/pending && -f $provisioning/setup-user && -f $provisioning/account-created && -f $provisioning/finalize-failed ]] || fail "$worker keeps pending owner and failure state"
  [[ ! -e $test_tmp/login-ready && $(<"$test_tmp/state") != "done" ]] || fail "$worker cannot release login or complete on failure"
  grep -Fxq "chown -R piowner:piowner $test_tmp/root/opt/omarchy-4-pi" "$TEST_CALLS" || fail "owner takes ownership of the update source checkout"
  (( $(grep -c '^chpasswd --encrypted$' "$TEST_CALLS") == 2 )) || fail "Imager hashes reach encrypted password setup"
  rm "$TEST_FAILURE"
  touch "$TEST_CLEANUP_FAILURE"
  status=0
  OMARCHY_PATH="$omarchy" bash "$test_tmp/owner-attempt" "$worker" || status=$?
  (( status == 24 )) || fail "$worker reports credential cleanup failure"
  [[ -f $provisioning/pending && -f $provisioning/setup-user && -f $provisioning/account-created ]] || fail "failed credential cleanup preserves the owner retry checkpoints"
  rm "$TEST_CLEANUP_FAILURE"
  OMARCHY_PATH="$omarchy" bash "$test_tmp/owner-attempt" "$worker" || fail "$worker retries successfully"
  (( $(grep -c '^useradd$' "$TEST_CALLS") == 1 )) || fail "$worker retries without recreating the account"
  ! grep -qx usermod "$TEST_CALLS" || fail "$worker resumes after completed account setup"
  [[ ! -e $provisioning/pending && ! -e $provisioning/finalize-failed && ! -e $provisioning/luks-rekey.state && -e $test_tmp/login-ready ]] || fail "$worker cleans pending state only after success"
  [[ -f $provisioning/groups && -d $provisioning/packages ]] || fail "cleanup keeps factory-reset groups and offline packages"
  [[ $(<"$test_tmp/root/home/piowner/.ssh/authorized_keys") == $'existing-key\nimager-key' ]] || fail "owner retries preserve existing keys and add Imager keys once"
  grep -qx keys-as-owner "$TEST_CALLS" || fail "authorized keys are written with the owner's privileges"
done
pass "both owner paths wait for hardware, retain failed setup, and retry without recreating accounts or replacing keys"

printf 'imager-key\n' >"$provisioning/authorized_keys"
keys=$test_tmp/root/home/piowner/.ssh/authorized_keys
victim=$test_tmp/other-keys
printf 'untouched\n' >"$victim"
for link_type in symbolic hard; do
  rm -f "$keys"
  if [[ $link_type == "symbolic" ]]; then ln -s "$victim" "$keys"; else ln "$victim" "$keys"; fi
  if OMARCHY_PATH="$omarchy" bash "$test_tmp/owner-attempt" install_authorized_keys; then
    fail "authorized keys reject a $link_type link"
  fi
  [[ $(<"$victim") == "untouched" ]] || fail "linked keys cannot modify another file"
done
rm -f "$keys"
mv "$test_tmp/root/home/piowner" "$test_tmp/redirected-home"
ln -s "$test_tmp/redirected-home" "$test_tmp/root/home/piowner"
if OMARCHY_PATH="$omarchy" bash "$test_tmp/owner-attempt" install_authorized_keys; then
  fail "authorized keys reject a redirected home"
fi
[[ ! -e $test_tmp/redirected-home/.ssh/authorized_keys ]] || fail "redirected home remains untouched"
rm "$test_tmp/root/home/piowner"
mv "$test_tmp/redirected-home" "$test_tmp/root/home/piowner"
pass "owner key installation refuses redirected homes and linked key files"

# Run the actual SSH option controls against temporary config and a generated
# disposable public key. Host-key generation and services never reach the host.
require_command ssh-keygen
ssh-keygen -q -t ed25519 -N '' -f "$test_tmp/test-key" </dev/null
sed -n '/^configure_imager_ssh() {$/,/^}$/p' "$ROOT/bin/omarchy-provision-owner" |
  sed -e "s|/etc/|$test_tmp/root/etc/|g" -e "s|/home/|$test_tmp/root/home/|g" >"$test_tmp/ssh-function"
ssh_config=$test_tmp/root/etc/ssh/sshd_config.d/10-omarchy-imager.conf
ssh_attempt() (
  set -euo pipefail
  source "$test_tmp/ssh-function"
  export imager_preseeded=true imager_ssh_enabled=$1 imager_ssh_password_auth=$2 username=piowner
  ssh-keygen() {
    if [[ $1 == "-A" ]]; then
      echo host-keys >>"$TEST_CALLS"
    else
      command ssh-keygen "$@"
    fi
  }
  sshd() {
    if [[ $1 == "-T" ]]; then
      awk '{ print tolower($1), tolower($2) }' "$ssh_config"
    fi
  }
  systemctl() { echo "systemctl $*" >>"$TEST_CALLS"; }
  ufw() { echo "ufw $*" >>"$TEST_CALLS"; }
  configure_imager_ssh
)
: >"$TEST_CALLS"
ssh_attempt false false || fail "disabled Imager SSH is a no-op"
[[ ! -e $ssh_config && ! -s $TEST_CALLS ]] || fail "Imager cannot enable SSH without opting in"
cp "$test_tmp/test-key.pub" "$test_tmp/root/home/piowner/.ssh/authorized_keys"
ssh_attempt true false || fail "key-only Imager SSH accepts a valid key"
grep -Fxq 'PasswordAuthentication no' "$ssh_config" && grep -Fxq 'KbdInteractiveAuthentication no' "$ssh_config" || fail "key-only SSH disables both password mechanisms"
grep -Fxq 'systemctl enable --now sshd.service' "$TEST_CALLS" || fail "opted-in SSH enables the service"
rm "$test_tmp/root/home/piowner/.ssh/authorized_keys"
: >"$TEST_CALLS"
if ssh_attempt true false; then fail "key-only SSH refuses missing keys"; fi
[[ ! -s $TEST_CALLS ]] || fail "missing keys cannot start SSH"
ssh_attempt true true || fail "explicit password-auth SSH needs no authorized key"
grep -Fxq 'PasswordAuthentication yes' "$ssh_config" || fail "explicit password SSH setting is retained"
pass "Imager SSH remains opt-in, key-only needs keys, and password authentication requires an explicit choice"
