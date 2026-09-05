#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/root"
export REAL_AWK REAL_INSTALL
REAL_AWK=$(command -v awk)
REAL_INSTALL=$(command -v install)
cat >"$test_tmp/bin/nproc" <<'SH'
#!/bin/bash
echo 4
SH
cat >"$test_tmp/bin/awk" <<'SH'
#!/bin/bash
if [[ ${2:-} == /proc/meminfo ]]; then
  if [[ $1 == *MemTotal* ]]; then echo "${TEST_TOTAL:-3900000}"; else echo "${TEST_AVAILABLE:-3300000}"; fi
else
  exec "$REAL_AWK" "$@"
fi
SH
cat >"$test_tmp/bin/omarchy-hw-raspberry-pi" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$test_tmp/bin/install" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $# == 3 && $1 == -Dm644 ]] || exit 1
case $3 in
  /etc/systemd/system/omarchy-pi-tune-guard.service|/etc/systemd/system/omarchy-pi-cpu-policy.service|/etc/makepkg.conf.d/50-omarchy-pi.conf|/etc/systemd/journald.conf.d/50-omarchy-pi.conf|/var/lib/omarchy/pi-performance-initialized) ;;
  /etc/systemd/zram-generator.conf.d/50-omarchy-pi.conf|/etc/sysctl.d/99-omarchy-pi-writeback.conf|/etc/systemd/user/app.slice.d/50-omarchy-pi.conf|/etc/systemd/oomd.conf.d/50-omarchy-pi.conf) ;;
  *) exit 1 ;;
esac
exec "$REAL_INSTALL" "$1" "$2" "$TEST_DEST$3"
SH
cat >"$test_tmp/bin/systemctl" <<'SH'
#!/bin/bash
[[ $* == 'enable omarchy-pi-cpu-policy.service' ]] || exit 1
SH
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$PATH" TEST_DEST="$test_tmp/root" OMARCHY_PATH="$ROOT"
(
  unset MAKEFLAGS CMAKE_BUILD_PARALLEL_LEVEL CARGO_BUILD_JOBS
  source "$ROOT/default/pi/build-budget.sh"
  [[ $MAKEFLAGS == -j2 && $CARGO_BUILD_JOBS == 2 && ${COMPRESSZST[*]} == 'zstd -c -T2 -3 -' ]] || fail "4GB compiler/compressor budgets"
)
(
  unset MAKEFLAGS CMAKE_BUILD_PARALLEL_LEVEL CARGO_BUILD_JOBS
  export TEST_AVAILABLE=800000
  source "$ROOT/default/pi/build-budget.sh"
  [[ $MAKEFLAGS == -j1 && $CARGO_BUILD_JOBS == 1 ]] || fail "memory pressure limits builds to one job"
)
(
  export MAKEFLAGS=-j1 CARGO_BUILD_JOBS=1 CMAKE_BUILD_PARALLEL_LEVEL=1
  source "$ROOT/default/pi/build-budget.sh"
  [[ $MAKEFLAGS == -j1 && $CARGO_BUILD_JOBS == 1 ]] || fail "explicit caller budgets are respected"
)
pass "makepkg defaults cap 4GB parallelism and compression without changing architecture flags"
apply_fixture() {
  if (( EUID == 0 )); then
    "$ROOT/bin/omarchy-apply-pi-performance"
  else
    sudo env PATH="$PATH" OMARCHY_PATH="$ROOT" TEST_DEST="$TEST_DEST" REAL_INSTALL="$REAL_INSTALL" \
      "$ROOT/bin/omarchy-apply-pi-performance"
  fi
}
apply_fixture
apply_fixture
cmp "$TEST_DEST/etc/systemd/system/omarchy-pi-tune-guard.service" "$ROOT/install/provisioning/omarchy-pi-tune-guard.service"
cmp "$TEST_DEST/etc/makepkg.conf.d/50-omarchy-pi.conf" "$ROOT/default/pi/makepkg.conf"
cmp "$TEST_DEST/etc/systemd/journald.conf.d/50-omarchy-pi.conf" "$ROOT/default/pi/journald.conf"
cmp "$TEST_DEST/etc/systemd/zram-generator.conf.d/50-omarchy-pi.conf" "$ROOT/default/pi/zram.conf"
cmp "$TEST_DEST/etc/systemd/user/app.slice.d/50-omarchy-pi.conf" "$ROOT/default/systemd/user/app.slice.d/10-oomd.conf"
if grep -Eq '^[[:space:]]*compression-algorithm[[:space:]]*=' "$ROOT/default/pi/zram.conf"; then
  fail "Pi zram must use the supported kernel default rather than force an absent backend"
fi
[[ ! -e $TEST_DEST/etc/systemd/user/session.slice.d ]] || fail "compositor session must not become an oomd kill candidate"
[[ ! -e $TEST_DEST/boot && ! -e $TEST_DEST/etc/hostname ]] || fail "performance setup must not touch boot clocks or identity"
pass "Pi setup installs idempotent named drop-ins without touching firmware or hostname"
mkdir -p "$test_tmp/cpufreq/policy0"
export OMARCHY_PI_CPUFREQ_ROOT="$test_tmp/cpufreq"
printf 'performance\n' >"$test_tmp/cpufreq/policy0/scaling_governor"
printf 'performance powersave schedutil ondemand\n' >"$test_tmp/cpufreq/policy0/scaling_available_governors"
"$ROOT/bin/omarchy-pi-cpu-policy"
[[ $(<"$test_tmp/cpufreq/policy0/scaling_governor") == schedutil ]] || fail "load-responsive governor selected"
printf 'powersave\n' >"$test_tmp/cpufreq/policy0/scaling_governor"
"$ROOT/bin/omarchy-pi-cpu-policy"
[[ $(<"$test_tmp/cpufreq/policy0/scaling_governor") == powersave ]] || fail "explicit governor preserved"
printf 'performance\n' >"$test_tmp/cpufreq/policy0/scaling_governor"
printf 'performance powersave\n' >"$test_tmp/cpufreq/policy0/scaling_available_governors"
"$ROOT/bin/omarchy-pi-cpu-policy"
[[ $(<"$test_tmp/cpufreq/policy0/scaling_governor") == performance ]] || fail "unsupported governor not written"
pass "boot CPU policy chooses a supported dynamic governor and preserves explicit alternatives"

cat >"$test_tmp/bin/git" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_GIT_LOG"
if [[ $1 == clone ]]; then
  mkdir -p "${@: -1}/.git" "${@: -1}/pkgbuilds"
else
  case $3 in
    status) [[ ${TEST_DIRTY:-0} == 0 ]] || echo ' M PKGBUILD' ;;
    remote) echo https://github.com/omacom/omarchy-pkgs.git ;;
    cat-file) exit 1 ;;
    fetch|checkout) ;;
    *) exit 1 ;;
  esac
fi
exit 0
SH
chmod +x "$test_tmp/bin/git"
export TEST_GIT_LOG="$test_tmp/recipe-calls" XDG_CACHE_HOME="$test_tmp/cache"
(
  source "$ROOT/install-rpi4.sh"
  unset OMARCHY_PKGS_PATH
  ensure_package_sources
)
pin=$(<"$ROOT/image/omarchy-pkgs.commit")
grep -F -- "checkout --detach $pin" "$TEST_GIT_LOG" >/dev/null || fail "default recipes use exact reviewed commit"
if grep -Eq ' pull( |$)' "$TEST_GIT_LOG"; then fail "recipe branch must not float"; fi
if (
  source "$ROOT/install-rpi4.sh"
  unset OMARCHY_PKGS_PATH
  export TEST_DIRTY=1
  ensure_package_sources
) >"$test_tmp/dirty-error" 2>&1; then
  fail "modified recipe checkout must not be overwritten"
fi
pass "Pi package recipes are pinned and local recipe edits are preserved"
