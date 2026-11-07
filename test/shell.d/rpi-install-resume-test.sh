#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
if (( EUID != 0 )); then
  skip "Pi installation checkpoint fixture requires root-owned disposable state"
  exit 0
fi
require_command git
require_command flock
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export TEST_INSTALL=$test_tmp
mkdir -p "$test_tmp/source/install/helpers" "$test_tmp/system" "$test_tmp/home"
cp "$ROOT/install-rpi4.sh" "$test_tmp/source/"
cp "$ROOT/install/helpers/rpi4-"*.sh "$test_tmp/source/install/helpers/"
git -C "$test_tmp/source" init -q
git -C "$test_tmp/source" add .
git -C "$test_tmp/source" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
cat >"$test_tmp/run" <<'SH'
#!/bin/bash
set -euo pipefail
source "$TEST_INSTALL/source/install-rpi4.sh"
# Run real orchestration and receipt checks, replacing only host operations.
check_preconditions() { prepare_install_request; }
existing_install() { [[ -e $TEST_INSTALL/system/installed ]]; }
install_checkpoint() {
  bash "$checkout/install/helpers/rpi4-install-state.sh" "$1" "$install_identity" "$TEST_INSTALL/checkpoint"
}
prepare_build_environment() { :; }
configure_arm_repositories() {
  echo repositories >>"$TEST_INSTALL/calls"
  [[ ${TEST_STOP:-} != repositories ]]
}
ensure_package_sources() { echo recipes >>"$TEST_INSTALL/calls"; }
install_official_packages() { echo runtime >>"$TEST_INSTALL/calls"; }
build_omarchy_packages() { echo build >>"$TEST_INSTALL/calls"; }
install_omarchy_packages() {
  echo core >>"$TEST_INSTALL/calls"
  touch "$TEST_INSTALL/system/installed"
}
write_rpi_profile() { echo profile >>"$TEST_INSTALL/calls"; }
seed_user_defaults() {
  echo defaults >>"$TEST_INSTALL/calls"
  echo shipped >"$TEST_INSTALL/home/config"
}
run_system_setup() {
  echo setup >>"$TEST_INSTALL/calls"
  [[ ${TEST_STOP:-} != setup ]]
}
main "$@"
SH
run_install() {
  env HOME="$test_tmp/home" USER="${TEST_USER:-fixture}" bash "$test_tmp/run" "$@" >"$test_tmp/result" 2>&1
}
reject() {
  local before after
  before=$(wc -l <"$test_tmp/calls")
  if run_install "$@"; then fail "unsafe installation request passed" "$(cat "$test_tmp/result")"; fi
  after=$(wc -l <"$test_tmp/calls")
  [[ $before == "$after" ]] || fail "rejected request mutated packages or user setup"
}
touch "$test_tmp/calls"
export TEST_STOP=setup
if run_install --minimal; then fail "required setup failure was hidden"; fi
[[ $(cat "$test_tmp/checkpoint/phase") == seeded ]] || fail "completed defaults were not checkpointed"
echo personal-change >"$test_tmp/home/config"
reject --minimal
reject --resume
reject --minimal --image --resume
TEST_USER=different reject --minimal --resume
printf '\n# changed source\n' >>"$test_tmp/source/install-rpi4.sh"
reject --minimal --resume
git -C "$test_tmp/source" checkout -- install-rpi4.sh
unset TEST_STOP
run_install --minimal --resume || fail "same installation could not resume" "$(cat "$test_tmp/result")"
[[ $(grep -c '^defaults$' "$test_tmp/calls") == 1 && $(cat "$test_tmp/home/config") == personal-change ]] || fail "resume replayed completed defaults"
[[ $(cat "$test_tmp/checkpoint/phase") == complete ]] || fail "successful retry did not complete"
reject --minimal
reject --minimal --resume
pass "interrupted setup resumes only with the same source, user and options, preserving seeded defaults"

# No caller can label a previously provisioned/legacy installation as pending.
rm -rf "$test_tmp/checkpoint"
reject --minimal
reject --minimal --resume
rm "$test_tmp/system/installed"
export TEST_STOP=repositories
if run_install --image; then fail "bootstrap failure was hidden"; fi
[[ $(cat "$test_tmp/checkpoint/phase") == started ]] || fail "early installation did not retain a retry checkpoint"
unset TEST_STOP
run_install --image --resume || fail "early bootstrap did not resume" "$(cat "$test_tmp/result")"
[[ $(grep -c '^defaults$' "$test_tmp/calls") == 1 ]] || fail "OEM setup seeded a factory user's defaults"
pass "early failures are resumable and completed or legacy installations cannot opt into replay"

rm -rf "$test_tmp/checkpoint"
rm "$test_tmp/system/installed"
export TEST_STOP=setup
if run_install --image; then fail "fixture setup failure was hidden"; fi
unset TEST_STOP
cp "$test_tmp/checkpoint/identity" "$test_tmp/identity"
rm "$test_tmp/checkpoint/identity"
ln -s "$test_tmp/identity" "$test_tmp/checkpoint/identity"
reject --image --resume
rm "$test_tmp/checkpoint/identity"
ln "$test_tmp/identity" "$test_tmp/checkpoint/identity"
reject --image --resume
rm "$test_tmp/checkpoint/identity"
cp "$test_tmp/identity" "$test_tmp/checkpoint/identity"
chmod 666 "$test_tmp/checkpoint/identity"
reject --image --resume
chmod 600 "$test_tmp/checkpoint/identity"
printf bad-phase >"$test_tmp/checkpoint/phase"
reject --image --resume
pass "symlinked, hardlinked, writable and malformed checkpoints cannot authorize resume"
