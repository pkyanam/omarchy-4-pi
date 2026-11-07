#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command bsdtar
require_command python3
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/source/.git" "$test_tmp/source/install/helpers" "$test_tmp/source/default/pi" "$test_tmp/state"
export TEST_TMP=$test_tmp TEST_CALLS="$test_tmp/calls" OMARCHY_RPI4_PROFILE="$test_tmp/profile"
export OMARCHY_RPI4_UPDATE_STATE="$test_tmp/state/installed" OMARCHY_UPDATE_LOGGED=1
export PATH="$test_tmp/bin:$PATH"
printf 'OMARCHY_RPI4_SOURCE=%q\nOMARCHY_PACMAN_PROFILE=rpi4\nOMARCHY_RPI4_PACKAGE_POLICY=stable-4.5\n' "$test_tmp/source" >"$OMARCHY_RPI4_PROFILE"
ln -s "$ROOT/install/helpers/rpi4-packages.sh" "$test_tmp/source/install/helpers/rpi4-packages.sh"
cat >"$test_tmp/bin/git" <<'SH'
#!/bin/bash
case $3 in
  rev-parse) printf '%040d\n' 123 ;;
  *) printf 'git %s\n' "$3" >>"$TEST_CALLS" ;;
esac
SH
cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$1" >>"$TEST_CALLS"
case $1 in
  env)
    shift
    while [[ ${1:-} == *=* ]]; do export "${1?}"; shift; done
    if [[ $1 == pacman ]]; then exec "$@"; fi
    ;;
  install)
    [[ $2 == -d && $3 == "$TEST_TMP/state" ]] || exit 91
    exec "$@" ;;
  tee)
    [[ $2 == "$OMARCHY_RPI4_UPDATE_STATE" ]] || exit 91
    exec "$@" ;;
  omarchy-hyprland-reload-guard|systemctl) ;;
  *) echo 'unexpected host sudo operation' >&2; exit 91 ;;
esac
SH
cat >"$test_tmp/bin/pacman" <<'SH'
#!/bin/bash
if [[ $1 == -U ]]; then
  echo core-install >>"$TEST_CALLS"
  [[ ${OMARCHY_RPI4_CORE_INSTALL:-} == 1 && ${OMARCHY_UPDATE_PACMAN:-} == 1 ]] || exit 91
  (( ${TEST_INSTALL_STATUS:-0} == 0 )) || exit "$TEST_INSTALL_STATUS"
  touch "$TEST_TMP/installed-artifacts"
elif [[ $1 == -Q ]]; then
  [[ -e $TEST_TMP/installed-artifacts ]] || { echo "$2 4.0.2-1"; exit; }
  case $2 in
    omarchy|omarchy-settings) echo "$2 4.5.0.pi4.1-1" ;;
    omarchy-keyring) echo "$2 20251027-1" ;;
    ttf-jetbrains-mono-nerd-basic) echo "$2 3.5.1-2" ;;
  esac
else
  exit 91
fi
SH
cat >"$test_tmp/source/default/pi/build-environment.sh" <<'SH'
omarchy_pi_prepare_build() { echo budget >>"$TEST_CALLS"; }
omarchy_pi_cleanup_build() { echo cleanup >>"$TEST_CALLS"; }
SH
cat >"$test_tmp/source/install-rpi4.sh" <<'SH'
ensure_package_sources() { echo recipes >>"$TEST_CALLS"; }
install_official_packages() {
  echo runtime >>"$TEST_CALLS"
  (( ${TEST_RUNTIME_STATUS:-0} == 0 ))
}
SH
cat >"$test_tmp/source/build-packages-rpi4.sh" <<'SH'
#!/bin/bash
set -e
echo rebuild >>"$TEST_CALLS"
source "$TEST_TMP/source/install/helpers/rpi4-packages.sh"
for name in "${omarchy_pi_core_packages[@]}"; do
  [[ ${TEST_MISSING_ARTIFACT:-} != "$name" ]] || continue
  case $name in
    omarchy|omarchy-settings) version=$omarchy_pi_core_version-1; arch=aarch64 ;;
    omarchy-keyring) version=20251027-1; arch=any ;;
    ttf-jetbrains-mono-nerd-basic) version=3.5.1-2; arch=any ;;
  esac
  printf 'pkgname = %s\npkgver = %s\narch = %s\n' "$name" "$version" "$arch" >"$TEST_TMP/.PKGINFO"
  bsdtar -czf "$OMARCHY_PACKAGE_OUTPUT/$name.pkg.tar.gz" -C "$TEST_TMP" .PKGINFO
done
SH
# External steps are mocked to prove ordering, while core artifact validation,
# retry/receipt logic and the updater's real control flow execute unchanged.
for step in omarchy-update-rpi4-guard omarchy-update-keyring omarchy-update-system-pkgs; do
  printf '#!/bin/bash\necho %s >>"$TEST_CALLS"\n' "$step" >"$test_tmp/bin/$step"
done
chmod +x "$test_tmp/bin/"* "$test_tmp/source/build-packages-rpi4.sh"
reject_update() {
  if env "$@" bash "$ROOT/bin/omarchy-update-rpi4" >"$test_tmp/update.log" 2>&1; then fail "incomplete Pi update unexpectedly succeeded" "$*"; fi
  [[ ! -e $OMARCHY_RPI4_UPDATE_STATE ]] || fail "incomplete core installation advanced its receipt"
}
reject_update TEST_RUNTIME_STATUS=1
[[ $(grep -c '^rebuild$' "$TEST_CALLS" || true) == 0 ]] || fail "missing runtime reached core build"
reject_update TEST_MISSING_ARTIFACT=omarchy-settings
[[ $(grep -c '^core-install$' "$TEST_CALLS" || true) == 0 ]] || fail "incomplete artifacts reached pacman"
reject_update TEST_INSTALL_STATUS=8
bash "$ROOT/bin/omarchy-update-rpi4" >"$test_tmp/update.log" 2>&1 || fail "Pi retry did not succeed" "$(cat "$test_tmp/update.log")"
[[ $(<"$OMARCHY_RPI4_UPDATE_STATE") == 0000000000000000000000000000000000000123 ]] || fail "Pi receipt did not record the installed source"
builds=$(grep -c '^rebuild$' "$TEST_CALLS")
bash "$ROOT/bin/omarchy-update-rpi4" >"$test_tmp/update.log" 2>&1
[[ $(grep -c '^rebuild$' "$TEST_CALLS") == "$builds" ]] || fail "current core rebuilt unnecessarily"
rm "$TEST_TMP/installed-artifacts"
bash "$ROOT/bin/omarchy-update-rpi4" >"$test_tmp/update.log" 2>&1
[[ $(grep -c '^rebuild$' "$TEST_CALLS") == "$((builds + 1))" ]] || fail "stale installed artifacts were hidden by a current source receipt"
pass "Pi core updates refuse unresolved runtime/incomplete artifacts, retry failed installs and repair stale versions behind current receipts"

# The top-level update must keep full system/runtime work before core, then
# restart the current shell before migrating. Every mocked leaf records order.
for step in omarchy-hw-raspberry-pi omarchy-update-lock omarchy-update-requires-free-space omarchy-update-pkg-prune omarchy-snapshot omarchy-update-stay-awake omarchy-update-dev omarchy-update-rpi4 omarchy-migrate omarchy-restart-shell omarchy-update-orphan-pkgs omarchy-update-analyze-logs omarchy-shell omarchy-update-restart omarchy-hook omarchy-update-mise omarchy-update-aur-pkgs omarchy-update-boot; do
  cat >"$test_tmp/bin/$step" <<'SH'
#!/bin/bash
step=${0##*/}
printf '%s %s\n' "$step" "$*" >>"$TEST_CALLS"
[[ ${TEST_FAIL_STEP:-} != "$step" ]]
SH
  chmod +x "$test_tmp/bin/$step"
done
mkdir -p "$test_tmp/runtime/bin"
ln -s "$test_tmp/bin/omarchy-update-restart" "$test_tmp/runtime/bin/omarchy-update-restart"
export OMARCHY_PATH="$test_tmp/runtime"
# No real privilege operations: also bypass the sudo timestamp subprocess.
cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
[[ $1 == true || $1 == -n ]] || exit 91
SH
: >"$TEST_CALLS"
bash "$ROOT/bin/omarchy-update" -y >"$test_tmp/top.log" 2>&1 || fail "Pi update orchestration failed" "$(cat "$test_tmp/top.log")"
python3 - "$TEST_CALLS" <<'PY'
from pathlib import Path
import sys
steps=Path(sys.argv[1]).read_text().splitlines()
a=steps.index('omarchy-update-rpi4 --prepare')
b=steps.index('omarchy-update-keyring')
c=steps.index('omarchy-update-system-pkgs')
d=steps.index('omarchy-update-rpi4 ')
e=steps.index('omarchy-restart-shell ')
f=steps.index('omarchy-migrate ')
assert a<b<c<d<e<f, steps
assert not any(s.startswith('omarchy-update-dev ') for s in steps)
PY
: >"$TEST_CALLS"
if TEST_FAIL_STEP=omarchy-restart-shell bash "$ROOT/bin/omarchy-update" -y >"$test_tmp/top.log" 2>&1; then fail "stale shell restart failure passed as a finished update"; fi
if grep -qx 'omarchy-migrate ' "$TEST_CALLS"; then fail "migrations ran against a stale Pi shell"; fi
pass "top updater upgrades stable system/runtime before local core and leaves migrations pending when the current shell cannot restart"
