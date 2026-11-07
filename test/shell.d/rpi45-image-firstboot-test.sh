#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
# Privileged production runs deliberately ignore fixture roots.
if (( EUID == 0 )); then
  skip "first-boot fixture requires an unprivileged Linux runner"
  exit 0
fi
if ! command -v flock >/dev/null || ! stat -c '%u %a' "$ROOT" >/dev/null 2>&1; then
  skip "first-boot fixture requires Linux flock/stat"
  exit 0
fi
umask 022
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
fixture="$test_tmp/omarchy"
stubs="$test_tmp/bin"
mkdir -p "$fixture/install/helpers" "$fixture/install/hardware" "$stubs"
cp "$ROOT/install/helpers/image-target.sh" "$ROOT/install/helpers/logging.sh" "$fixture/install/helpers/"
cat >"$fixture/install/hardware/check.sh" <<'LEAF'
[[ -f $OMARCHY_IMAGE_ROOT/etc/pacman.d/gnupg/local-generated ]] || return 1
printf 'hardware\n' >>"$TEST_CALLS"
LEAF
cat >"$stubs/pacman-key" <<'STUB'
#!/bin/bash
printf 'pacman-key %s\n' "$*" >>"$TEST_CALLS"
[[ ${TEST_INIT_FAIL:-0} == 0 ]] || exit 23
if [[ $* == *--init ]]; then
  mkdir -p "$OMARCHY_IMAGE_ROOT/etc/pacman.d/gnupg"
  touch "$OMARCHY_IMAGE_ROOT/etc/pacman.d/gnupg/local-generated"
fi
STUB
printf '#!/bin/bash\nprintf "aarch64\\n"\n' >"$stubs/omarchy-hw-platform"
chmod +x "$stubs/"*
export TEST_CALLS="$test_tmp/calls"
new_root() {
  root="$test_tmp/$1"
  mkdir -p "$root/var/lib/omarchy/image" "$root/etc/pacman.d" "$root/var/log"
  printf 'format=1\nplatform=aarch64\n' >"$root/var/lib/omarchy/image/target"
  printf 'install/hardware/check.sh\n' >"$root/var/lib/omarchy/image/deferred-steps"
  touch "$root/var/lib/omarchy/image/pacman-keyring"
}
boot() {
  OMARCHY_IMAGE_ROOT="$root" OMARCHY_PATH="$fixture" PATH="$stubs:$PATH" \
    "$BASH" "$ROOT/bin/omarchy-provision-hardware"
}
new_root retry
status=0
TEST_INIT_FAIL=1 boot >"$test_tmp/init-failure.log" 2>&1 || status=$?
(( status == 75 )) || fail "failed keyring initialization is retryable"
[[ -f $root/var/lib/omarchy/image/pacman-keyring && -s $root/var/lib/omarchy/image/deferred-steps ]] || fail "keyring failure retains all pending work"
! grep -Fx hardware "$TEST_CALLS" >/dev/null || fail "hardware may not run before keyring initialization"
: >"$TEST_CALLS"
boot >"$test_tmp/retry.log" 2>&1 || fail "retry initializes the keyring and completes hardware"
expected="pacman-key --gpgdir $root/etc/pacman.d/gnupg --init"$'\n'"pacman-key --gpgdir $root/etc/pacman.d/gnupg --populate"$'\nhardware'
[[ $(<"$TEST_CALLS") == "$expected" && ! -e $root/var/lib/omarchy/image/pacman-keyring && ! -e $root/var/lib/omarchy/image/deferred-steps ]] || fail "successful retry initializes trust before hardware and clears pending work"
pass "per-device keyring initialization gates hardware and retains retry state on failure"

for hazard in request keyring parent; do
  new_root "$hazard"
  victim="$test_tmp/victim-$hazard"
  mkdir -p "$victim"
  printf 'unrelated\n' >"$victim/keep"
  case $hazard in
    request)
      rm "$root/var/lib/omarchy/image/pacman-keyring"
      ln -s "$victim/keep" "$root/var/lib/omarchy/image/pacman-keyring"
      ;;
    keyring) ln -s "$victim" "$root/etc/pacman.d/gnupg" ;;
    parent)
      rmdir "$root/etc/pacman.d"
      ln -s "$victim" "$root/etc/pacman.d"
      ;;
  esac
  : >"$TEST_CALLS"
  if boot >"$test_tmp/$hazard.log" 2>&1; then
    fail "first boot must reject a symlinked $hazard"
  fi
  [[ -s $victim/keep && ! -s $TEST_CALLS ]] || fail "unsafe $hazard cannot initialize trust or remove caller data"
done
pass "untrusted keyring requests and symlinked keyring paths fail before destructive work"
