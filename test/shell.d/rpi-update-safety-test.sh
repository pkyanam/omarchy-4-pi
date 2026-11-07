#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command git
unset OMARCHY_RPI4_PACKAGE_POLICY OMARCHY_PACMAN_PROFILE

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/source"
export OMARCHY_RPI4_PROFILE="$test_tmp/profile" CALL_LOG="$test_tmp/calls"
export REAL_GIT
REAL_GIT=$(command -v git)
"$REAL_GIT" -C "$test_tmp/source" init -q -b main
"$REAL_GIT" -C "$test_tmp/source" -c user.name=Test -c user.email=test@example.invalid commit -qm initial --allow-empty
"$REAL_GIT" -C "$test_tmp/source" remote add origin https://github.com/pkyanam/omarchy-4-pi.git
"$REAL_GIT" -C "$test_tmp/source" update-ref refs/remotes/origin/main HEAD
"$REAL_GIT" -C "$test_tmp/source" branch --set-upstream-to=origin/main main >/dev/null
write_profile() {
  printf 'OMARCHY_RPI4_SOURCE=%q\nOMARCHY_PACMAN_PROFILE=rpi4\nOMARCHY_RPI4_PACKAGE_POLICY=stable-4.5\n' "$test_tmp/source" >"$OMARCHY_RPI4_PROFILE"
}
write_profile

# Git inspection is real. Network/source mutations and all privileged/package
# operations stop at logging doubles; a failed guard can never touch the host.
cat >"$test_tmp/bin/git" <<'SH'
#!/bin/bash
# Only the guard's read-only queries may reach real Git. Unknown invocation
# forms (including clone without -C) are rejected as possible mutations.
if [[ ${1:-} == "-C" ]]; then
  case ${3:-} in
    symbolic-ref|rev-parse|status) exec "$REAL_GIT" "$@" ;;
    remote)
      if [[ ${4:-} == "get-url" ]]; then exec "$REAL_GIT" "$@"; fi ;;
  esac
fi
printf 'git %s\n' "$*" >>"$CALL_LOG"
exit 91
SH
cat >"$test_tmp/bin/uname" <<'SH'
#!/bin/bash
printf '%s\n' "${TEST_ARCH:-aarch64}"
SH
cat >"$test_tmp/bin/omarchy-hw-aarch64" <<'SH'
#!/bin/bash
[[ ${TEST_ARCH:-aarch64} == "aarch64" ]]
SH
cat >"$test_tmp/bin/pacman-conf" <<'SH'
#!/bin/bash
case "$*" in
  Architecture) printf '%s\n' "${TEST_PACMAN_ARCH:-aarch64}" ;;
  --repo-list) printf '%s\n' "${TEST_REPOS-omarchy
core
extra
alarm}" ;;
  IgnorePkg) printf '%s\n' "${TEST_IGNOREPKG-omarchy omarchy-settings omarchy-dev omarchy-settings-dev}" ;;
  *)
    [[ $# == 3 && $1 == "--repo" ]] || exit 91
    case $3 in
      Server)
        if [[ $2 == "omarchy" ]]; then
          printf '%s\n' "${TEST_OMARCHY_SERVER:-https://pkgs.omarchy.org/stable/aarch64}"
        else
          printf '%s\n' "${TEST_ARM_SERVER:-https://arm-stable-mirror.omarchy.org/aarch64/$2}"
        fi ;;
      CacheServer) printf '%s' "${TEST_CACHE_SERVER:-}" ;;
      SigLevel) printf '%s\n' "${TEST_SIGLEVEL:-Required DatabaseOptional}" ;;
      *) exit 91 ;;
    esac ;;
esac
SH
cat >"$test_tmp/bin/omarchy-hw-raspberry-pi" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALL_LOG"
SH
for command in pacman pacman-key omarchy-update-pacman curl wget; do
  cat >"$test_tmp/bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$CALL_LOG"
exit 91
SH
done
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"

omarchy-update-rpi4-guard
pass "real clean Pi main checkout and signed stable ARM repository contract pass preflight"
reject() {
  : >"$CALL_LOG"
  if "$@" >"$test_tmp/rejected" 2>&1; then
    fail "unsafe update preflight must fail" "$*"
  fi
  [[ ! -s $CALL_LOG ]] || fail "unsafe update reached source, repository or package mutation" "$(cat "$CALL_LOG")"
}
reject env TEST_ARCH=x86_64 omarchy-update-rpi4-guard
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update-rpi4-guard
reject env TEST_REPOS=$'core\nomarchy\nextra\nalarm' omarchy-update-rpi4-guard
reject env TEST_REPOS=$'omarchy\ncore\nextra\nalarm\naur' omarchy-update-rpi4-guard
reject env TEST_REPOS=$'omarchy\ncore\nextra' omarchy-update-rpi4-guard
reject env TEST_IGNOREPKG='omarchy omarchy-dev omarchy-settings-dev' omarchy-update-rpi4-guard
reject env TEST_OMARCHY_SERVER=https://pkgs.omarchy.org/edge/aarch64 omarchy-update-rpi4-guard
reject env TEST_OMARCHY_SERVER=https://stable-mirror.omarchy.org/core/os/aarch64 omarchy-update-rpi4-guard
reject env TEST_ARM_SERVER=https://mirror.archlinuxarm.org/aarch64/core omarchy-update-rpi4-guard
reject env TEST_CACHE_SERVER=https://mirror.archlinuxarm.org/aarch64/core omarchy-update-rpi4-guard
for signatures in Never 'Required TrustAll' 'PackageOptional DatabaseOptional'; do
  reject env TEST_SIGLEVEL="$signatures" omarchy-update-rpi4-guard
done
pass "mixed, rolling, reordered or incomplete repositories, unprotected core and unsafe trust fail before mutation"

"$REAL_GIT" -C "$test_tmp/source" remote set-url origin https://github.com/omacom/omarchy.git
reject omarchy-update-rpi4-guard
"$REAL_GIT" -C "$test_tmp/source" remote set-url origin https://github.com/pkyanam/omarchy-4-pi.git
"$REAL_GIT" -C "$test_tmp/source" checkout -qb codex/omarchy-4.5-pi4
reject omarchy-update-rpi4-guard
"$REAL_GIT" -C "$test_tmp/source" checkout -q main
"$REAL_GIT" -C "$test_tmp/source" branch --unset-upstream
reject omarchy-update-rpi4-guard
"$REAL_GIT" -C "$test_tmp/source" branch --set-upstream-to=origin/main main >/dev/null
touch "$test_tmp/source/local-edit"
reject omarchy-update-rpi4-guard
rm "$test_tmp/source/local-edit"
reject env OMARCHY_RPI4_PROFILE="$test_tmp/missing" omarchy-update-rpi4-guard
pass "wrong origin, candidate branch, missing tracking, dirty source and missing profile fail closed"

# Old cards must be refused at every entry point before even fetching source.
# Retry/receipt and strict artifact-pair behavior live in rpi45-updates-test.sh.
for profile in missing-policy rolling wrong-profile; do
  case $profile in
    missing-policy) printf 'OMARCHY_PACMAN_PROFILE=rpi4\n' >"$OMARCHY_RPI4_PROFILE" ;;
    rolling) printf 'OMARCHY_PACMAN_PROFILE=rpi4\nOMARCHY_RPI4_PACKAGE_POLICY=rolling\n' >"$OMARCHY_RPI4_PROFILE" ;;
    wrong-profile) printf 'OMARCHY_PACMAN_PROFILE=aarch64\nOMARCHY_RPI4_PACKAGE_POLICY=stable-4.5\n' >"$OMARCHY_RPI4_PROFILE" ;;
  esac
  printf 'OMARCHY_RPI4_SOURCE=%q\n' "$test_tmp/source" >>"$OMARCHY_RPI4_PROFILE"
  for mode in all source packages; do
    reject omarchy-update-rpi4-guard "$mode"
  done
  for command in omarchy-update omarchy-update-rpi4 omarchy-update-system-pkgs omarchy-update-keyring; do
    reject "$command"
    grep -F 'to spare media' "$test_tmp/rejected" >/dev/null ||
      fail "legacy update refusal must explain fresh-media recovery" "$command: $(cat "$test_tmp/rejected")"
  done
  reject omarchy-update-rpi4 --prepare
  # A caller environment must not certify a legacy file as a 4.5 profile.
  if [[ $profile == "missing-policy" ]]; then
    reject env OMARCHY_RPI4_PACKAGE_POLICY=stable-4.5 OMARCHY_PACMAN_PROFILE=rpi4 omarchy-update-rpi4-guard
  fi
done
write_profile
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update -y
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update-system-pkgs
reject env TEST_PACMAN_ARCH=x86_64 omarchy-update-keyring
pass "legacy rolling profiles stop all update entry points before source fetch, trust changes or package mutation"

: >"$CALL_LOG"
omarchy-update-keyring
grep -Fx 'sudo env OMARCHY_UPDATE_PACMAN=1 pacman -Sy --needed --noconfirm archlinuxarm-keyring omarchy-keyring' "$CALL_LOG" >/dev/null || fail "Pi refreshes both stable ARM and Omarchy keyrings"
grep -Fx 'sudo pacman-key --populate archlinuxarm omarchy' "$CALL_LOG" >/dev/null || fail "Pi populates both installed vendor keyrings"
if grep -E 'archlinux-keyring|recv-keys|lsign-key' "$CALL_LOG"; then
  fail "Pi stable keyring refresh must not import x86 or ad-hoc trust"
fi
pass "Pi keyring update requests signed ARM and Omarchy trust without x86 keys"
reject "$ROOT/bin/omarchy-upgrade-to-quattro" --yes
pass "legacy x86 upgrader rejects aarch64 before installation"
