#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/source"
export OMARCHY_RPI4_PROFILE="$test_tmp/profile" CALL_LOG="$test_tmp/calls"
printf 'OMARCHY_RPI4_SOURCE=%q\n' "$test_tmp/source" >"$OMARCHY_RPI4_PROFILE"
git -C "$test_tmp/source" init -q -b main
git -C "$test_tmp/source" -c user.name=Test -c user.email=test@example.invalid commit -qm initial --allow-empty
git -C "$test_tmp/source" remote add origin https://github.com/pkyanam/omarchy-4-pi.git
git -C "$test_tmp/source" update-ref refs/remotes/origin/main HEAD
git -C "$test_tmp/source" branch --set-upstream-to=origin/main main >/dev/null
cat >"$test_tmp/bin/uname" <<'SH'
#!/bin/bash
echo "${TEST_ARCH:-aarch64}"
SH
cat >"$test_tmp/bin/pacman-conf" <<'SH'
#!/bin/bash
case "$*" in
  Architecture) echo "${TEST_PACMAN_ARCH:-aarch64}" ;;
  --repo-list) printf 'core\nextra\nalarm\naur\n'; [[ -z ${TEST_EXTRA_REPO:-} ]] || echo "$TEST_EXTRA_REPO" ;;
  *) echo "${TEST_SERVER:-https://mirror.archlinuxarm.org/aarch64/core}" ;;
esac
exit 0
SH
cat >"$test_tmp/bin/omarchy-hw-raspberry-pi" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
SH
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
omarchy-update-rpi4-guard
pass "canonical Pi checkout and ARM repositories pass update preflight"
reject() {
  if "$@" >"$test_tmp/rejected" 2>&1; then fail "unsafe update preflight must fail" "$*"; fi
}
reject env TEST_ARCH=x86_64 omarchy-update-rpi4-guard
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update-rpi4-guard
reject env TEST_EXTRA_REPO=omarchy omarchy-update-rpi4-guard
reject env TEST_SERVER=https://stable-mirror.omarchy.org/core/os/aarch64 omarchy-update-rpi4-guard
git -C "$test_tmp/source" remote set-url origin https://github.com/omacom/omarchy.git
reject omarchy-update-rpi4-guard
git -C "$test_tmp/source" remote set-url origin https://github.com/pkyanam/omarchy-4-pi.git
git -C "$test_tmp/source" checkout -qb wrong
reject omarchy-update-rpi4-guard
git -C "$test_tmp/source" checkout -q main
touch "$test_tmp/source/local-edit"
reject omarchy-update-rpi4-guard
rm "$test_tmp/source/local-edit"
reject env OMARCHY_RPI4_PROFILE="$test_tmp/missing" omarchy-update-rpi4-guard
pass "wrong architecture, repositories, origin, branch, dirty source, and missing profile are refused"
: >"$CALL_LOG"
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update -y
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update-system-pkgs
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update-keyring
[[ ! -s $CALL_LOG ]] || fail "unsafe updates must stop before privileged operations"
pass "top-level, direct package, and keyring updates fail before privileged mutations"
omarchy-update-keyring
grep -Fx 'pacman -Sy --needed --noconfirm archlinuxarm-keyring' "$CALL_LOG" >/dev/null || fail "Pi update refreshes the ARM keyring"
if grep -E 'archlinux-keyring|recv-keys|lsign-key' "$CALL_LOG"; then fail "Pi keyring update must not import x86 trust"; fi
pass "Pi keyring path never requests x86 keys"
reject "$ROOT/bin/omarchy-upgrade-to-quattro" --yes
pass "legacy x86 upgrader rejects aarch64 before installation"

# Exercise installation failure and retry after HEAD is already current.
export REAL_GIT
REAL_GIT=$(command -v git)
cat >"$test_tmp/bin/git" <<'SH'
#!/bin/bash
[[ ${3:-} != "fetch" ]] || exit 0
exec "$REAL_GIT" "$@"
SH
cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
case "$1" in
  pacman) exit "${TEST_INSTALL_STATUS:-0}" ;;
  install|tee) exec "$@" ;;
  *) exit 1 ;;
esac
SH
cat >"$test_tmp/source/install-rpi4.sh" <<'SH'
#!/bin/bash
ensure_package_sources() { :; }
install_arm_packages() { echo runtime-dependencies >>"$CALL_LOG"; }
SH
cat >"$test_tmp/source/build-packages-rpi4.sh" <<'SH'
#!/bin/bash
echo rebuild >>"$CALL_LOG"
touch "$OMARCHY_PACKAGE_OUTPUT/omarchy-1-any.pkg.tar.zst"
SH
chmod +x "$test_tmp/bin/git" "$test_tmp/source/build-packages-rpi4.sh"
git -C "$test_tmp/source" add .
git -C "$test_tmp/source" -c user.name=Test -c user.email=test@example.invalid commit -qm fixtures
git -C "$test_tmp/source" update-ref refs/remotes/origin/main HEAD
export OMARCHY_RPI4_UPDATE_STATE="$test_tmp/state/installed"
: >"$CALL_LOG"
reject env TEST_INSTALL_STATUS=8 omarchy-update-rpi4
[[ ! -e $OMARCHY_RPI4_UPDATE_STATE ]] || fail "failed installation cannot mark the source installed"
omarchy-update-rpi4
[[ $(<"$OMARCHY_RPI4_UPDATE_STATE") == "$(git -C "$test_tmp/source" rev-parse HEAD)" ]] || fail "successful install records its exact source"
omarchy-update-rpi4
[[ $(grep -c '^rebuild$' "$CALL_LOG") == 2 ]] || fail "failed installs retry; successful installs skip needless rebuilds"
grep -Fx runtime-dependencies "$CALL_LOG" >/dev/null || fail "updates reconcile minimal runtime dependencies"
pass "core package install failures remain retryable after checkout advances"
