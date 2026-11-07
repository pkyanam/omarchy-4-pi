#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Regressions: bootstrap builds escaping the RAM budget, tmpfs staging, btrfs
# inode false alarms, unsafe caller-directory cleanup, scopes outside app.slice,
# health-report loss on GLX failure, inactive/ambiguous firmware, and re-seeding
# owner choices. No package, service, device or live desktop operation here.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/build parent" "$test_tmp/home"
export HOME="$test_tmp/home" OMARCHY_PI_MEMINFO="$test_tmp/meminfo" TEST_TMP="$test_tmp"
export TEST_FSTYPE=ext4 TEST_INODES=100000 TEST_FREE_INODES=90000 TEST_FREE_KIB=20000000
cat >"$test_tmp/bin/nproc" <<'SH'
#!/bin/bash
echo "${TEST_CPUS:-4}"
SH
cat >"$test_tmp/bin/findmnt" <<'SH'
#!/bin/bash
printf '%s\n' "$TEST_FSTYPE"
SH
cat >"$test_tmp/bin/df" <<'SH'
#!/bin/bash
if [[ $1 == -Pi ]]; then
  printf 'Filesystem Inodes IUsed IFree IUse%% Mounted\n/dev/fixture %s 0 %s - /fixture\n' "$TEST_INODES" "$TEST_FREE_INODES"
else
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/fixture 30000000 1 %s 1%% /fixture\n' "$TEST_FREE_KIB"
fi
SH
cat >"$test_tmp/bin/omarchy-hw-raspberry-pi" <<'SH'
#!/bin/bash
exit "${TEST_NOT_PI:-0}"
SH
cat >"$test_tmp/bin/systemd-run" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_TMP/scope-argv"
exit "${TEST_SCOPE_STATUS:-0}"
SH
cat >"$test_tmp/bin/glxinfo" <<'SH'
#!/bin/bash
touch "$TEST_TMP/glx-called"
[[ ${TEST_GLX_FAIL:-0} == 0 ]] || exit 7
printf 'OpenGL renderer string: V3D 4.2: fixture\n'
SH
cat >"$test_tmp/bin/free" <<'SH'
#!/bin/bash
printf 'Mem: 4Gi 1Gi 3Gi\n'
SH
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$PATH"

printf 'MemTotal: 3900000 kB\nMemAvailable: 3300000 kB\n' >"$OMARCHY_PI_MEMINFO"
(
  unset MAKEFLAGS CARGO_BUILD_JOBS CMAKE_BUILD_PARALLEL_LEVEL ZSTD_NBTHREADS XZ_OPT
  source "$ROOT/default/pi/build-budget.sh"
  [[ $MAKEFLAGS == "-j2" && $CARGO_BUILD_JOBS == 2 && $CMAKE_BUILD_PARALLEL_LEVEL == 2 && ${COMPRESSZST[*]} == 'zstd -c -T2 -3 -' ]] || fail "4GB first build budget"
  printf 'MemTotal: 7900000 kB\nMemAvailable: 7000000 kB\n' >"$OMARCHY_PI_MEMINFO"
  unset MAKEFLAGS CARGO_BUILD_JOBS CMAKE_BUILD_PARALLEL_LEVEL ZSTD_NBTHREADS XZ_OPT COMPRESSZST COMPRESSXZ
  export TEST_CPUS=16
  source "$ROOT/default/pi/build-budget.sh"
  [[ $OMARCHY_PI_BUILD_JOBS == 3 ]] || fail "8GB remains at most three jobs on a many-core builder"
  printf 'MemTotal: 7900000 kB\nMemAvailable: 800000 kB\n' >"$OMARCHY_PI_MEMINFO"
  export MAKEFLAGS='-k -j32' CARGO_BUILD_JOBS=32 CMAKE_BUILD_PARALLEL_LEVEL=32
  source "$ROOT/default/pi/build-budget.sh"
  [[ $MAKEFLAGS == *'-j1' && $CARGO_BUILD_JOBS == 1 && $CMAKE_BUILD_PARALLEL_LEVEL == 1 ]] || fail "low available RAM caps loose caller budgets"
)
printf 'MemTotal: 3900000 kB\nMemAvailable: 3300000 kB\n' >"$OMARCHY_PI_MEMINFO"
(
  export MAKEFLAGS='-k --jobs=1' CARGO_BUILD_JOBS=1 CMAKE_BUILD_PARALLEL_LEVEL=1
  COMPRESSZST=(zstd -c -T1 -)
  COMPRESSXZ=(xz -c -T1 -)
  source "$ROOT/default/pi/build-budget.sh"
  [[ $MAKEFLAGS == '-k --jobs=1 -j1' && $CARGO_BUILD_JOBS == 1 && $CMAKE_BUILD_PARALLEL_LEVEL == 1 && ${COMPRESSZST[*]} == 'zstd -c -T1 -3 -' && $XZ_OPT == '-T1 -3 --memlimit-compress=25%' ]] || fail "tighter explicit compiler/compression limits survive"
  export XZ_OPT='--threads=1 --memlimit-compress=128MiB'
  source "$ROOT/default/pi/build-budget.sh"
  [[ $XZ_OPT == '-T1 -3 --memlimit-compress=128MiB' ]] || fail "tighter explicit xz memory limit survives"
)
pass "shared bootstrap budget caps 4GB, 8GB and pressure cases while preserving tighter limits"

source "$ROOT/default/pi/build-environment.sh"
export OMARCHY_PI_BUILD_PARENT="$test_tmp/build parent" OMARCHY_PI_MAKEPKG_BASE_CONF="$test_tmp/base.conf"
printf 'COMPRESSZST=(zstd -c -T0 -20 -)\n' >"$OMARCHY_PI_MAKEPKG_BASE_CONF"
printf 'unrelated\n' >"$OMARCHY_PI_BUILD_PARENT/sentinel"
export PKGDEST="$test_tmp/output packages"
export BUILDDIR=/tmp/unsafe-build-override SRCDEST=/tmp/unsafe-source-override
omarchy_pi_prepare_build fixture
owned=$OMARCHY_PI_BUILD_WORK
[[ $TMPDIR == "$owned/tmp" && $BUILDDIR == "$owned/build" && $SRCDEST == "$owned/cache/sources" && -d $OMARCHY_PI_BUILD_CACHE && -f $OMARCHY_PI_MAKEPKG_CONF ]] || fail "private disk work/cache established before staging"
(
  # shellcheck disable=SC1090 # Generated private makepkg config is the fixture subject.
  source "$OMARCHY_PI_MAKEPKG_CONF"
  [[ $BUILDDIR == "$owned/build" && $SRCDEST == "$owned/cache/sources" && $PKGDEST == "$test_tmp/output packages" && ${COMPRESSZST[*]} == 'zstd -c -T2 -3 -' ]] || fail "first makepkg config carries disk paths and bounded compression"
  omarchy_pi_cleanup_build
  [[ -d $owned ]] || fail "subshell cleanup must not delete parent workspace"
)
omarchy_pi_prepare_build fixture
[[ $OMARCHY_PI_BUILD_WORK == "$owned" ]] || fail "same-process preparation is idempotent"
printf 'changed\n' >"$owned/.omarchy-pi-build-owner"
if omarchy_pi_cleanup_build 2>"$test_tmp/cleanup-refusal"; then fail "changed ownership marker must refuse cleanup"; fi
printf '%s\n' "$_omarchy_pi_build_owner" >"$owned/.omarchy-pi-build-owner"
printf 'package\n' >"$PKGDEST/retained"
omarchy_pi_cleanup_build
[[ ! -e $owned && -f $OMARCHY_PI_BUILD_PARENT/sentinel && -f $PKGDEST/retained ]] || fail "cleanup deletes only its child, preserving caller parent and persistent outputs"
[[ $BUILDDIR == /tmp/unsafe-build-override && $SRCDEST == /tmp/unsafe-source-override ]] || fail "cleanup did not restore caller environment"
pass "private build storage, makepkg integration, explicit outputs and ownership cleanup"

# A failed marker write can leave a nonempty file (ENOSPC/EDQUOT).
(
  printf() {
    if [[ ${1:-} == '%s\n' && ${2:-} == "$$:"* ]]; then
      builtin printf partial
      return 1
    fi
    builtin printf "$@"
  }
  if omarchy_pi_prepare_build marker-failure; then fail "partial ownership marker write succeeded"; fi
)
if compgen -G "$OMARCHY_PI_BUILD_PARENT/omarchy-pi-marker-failure.*" >/dev/null; then
  fail "failed ownership marker write retained its build workspace"
fi
[[ -f $OMARCHY_PI_BUILD_PARENT/sentinel ]] || fail "marker cleanup removed caller files"
pass "failed ownership marker writes remove only their new workspace"

for filesystem in tmpfs ramfs overlay; do
  if TEST_FSTYPE=$filesystem omarchy_pi_prepare_build fixture >"$test_tmp/refused-$filesystem" 2>&1; then fail "unverified $filesystem build storage accepted"; fi
done
if TEST_FREE_KIB=1 omarchy_pi_prepare_build fixture >"$test_tmp/refused-space" 2>&1; then fail "low disk space accepted"; fi
TEST_FSTYPE=btrfs TEST_INODES=0 TEST_FREE_INODES=0 omarchy_pi_prepare_build fixture
omarchy_pi_cleanup_build
if TEST_FSTYPE=ext4 TEST_FREE_INODES=0 omarchy_pi_prepare_build fixture >"$test_tmp/refused-inodes" 2>&1; then fail "exhausted ext4 inodes accepted"; fi
if TEST_FSTYPE=ext4 TEST_INODES=0 TEST_FREE_INODES=0 omarchy_pi_prepare_build fixture >"$test_tmp/refused-fixed-inodes" 2>&1; then fail "unknown ext4 fixed inode capacity accepted"; fi
pass "storage rejects tmpfs/overlay and capacity exhaustion while accepting dynamic btrfs inodes"

"$BASH" "$ROOT/bin/omarchy-pi-run" --plan -- printf '%s' 'literal $HOME; no expansion' >"$test_tmp/plan"
[[ ! -e $test_tmp/scope-argv ]] || fail "scope plan performed a live operation"
"$BASH" "$ROOT/bin/omarchy-pi-run" -- printf '%s' 'literal $HOME; no expansion'
grep -Fx -- '--slice=app.slice' "$test_tmp/scope-argv" >/dev/null || fail "workload escapes app-scope oomd coverage"
grep -Fx 'literal $HOME; no expansion' "$test_tmp/scope-argv" >/dev/null || fail "scope argv changed"
status=0
TEST_SCOPE_STATUS=9 "$BASH" "$ROOT/bin/omarchy-pi-run" -- true || status=$?
(( status == 9 )) || fail "scope creation failure must propagate"
pass "workloads enter app.slice and preserve argv and scope failures"

export OMARCHY_RPI_HWMON_ROOT="$test_tmp/no-sensor" OMARCHY_RPI_THERMAL_ROOT="$test_tmp/no-sensor" OMARCHY_RPI_MODEL_PATH="$test_tmp/model"
printf 'Raspberry Pi 4 Model B Rev 1.5\0' >"$OMARCHY_RPI_MODEL_PATH"
TEST_GLX_FAIL=1 DISPLAY=:fixture "$BASH" "$ROOT/bin/omarchy-pi-status" >"$test_tmp/health-failed-glx"
grep -F 'Root disk:' "$test_tmp/health-failed-glx" >/dev/null || fail "GLX failure suppressed native health report"
grep -F 'GLX query failed' "$test_tmp/health-failed-glx" >/dev/null || fail "GLX failure was reported as healthy"
DISPLAY=:fixture "$BASH" "$ROOT/bin/omarchy-pi-status" >"$test_tmp/health-glx"
grep -F 'V3D 4.2: fixture (GLX/XWayland; compositor rendering unverified)' "$test_tmp/health-glx" >/dev/null || fail "GLX renderer is truncated or mislabeled as compositor proof"
rm "$test_tmp/glx-called"
env -u DISPLAY WAYLAND_DISPLAY=fixture "$BASH" "$ROOT/bin/omarchy-pi-status" >"$test_tmp/health-wayland"
[[ ! -e $test_tmp/glx-called ]] || fail "Wayland-only session attempted an unusable GLX query"
pass "failed/Wayland-only GLX diagnostics retain the complete native health report"

PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import os
from pathlib import Path
import runpy
f = runpy.run_path(str(Path(os.environ['ROOT']) / 'default/pi/firmware-config.py'))
root = Path(os.environ['TEST_TMP'])
def effective(data):
  active = True
  scalars = {}
  overlays = []
  for line in data.decode().splitlines():
    if line.startswith('['): active = line in ('[all]', '[pi4]')
    elif active and '=' in line and not line.startswith('#'):
      key, value = line.split('=', 1)
      scalars[key] = value
      if key == 'dtoverlay' and value.startswith('vc4-kms'): overlays.append(value)
  return scalars, overlays
original = b'arm_freq=1500\ngpu_mem=64\n[pi5]\ndtoverlay=vc4-kms-v3d\n[all]\ndtparam=audio=on\ndtparam=audio=off\n[none]\n'
updated = f['proposed'](original)
values, overlays = effective(updated)
assert values['max_framebuffers'] == '2' and values['disable_fw_kms_setup'] == '1' and values['dtparam'] == 'audio=on'
assert overlays == ['vc4-kms-v3d'] and updated.startswith(original.rstrip(b'\n'))
assert f['proposed'](updated) == updated
existing = b'[all]\ndtoverlay=vc4-kms-v3d-pi4,cma-256\n[pi5]\ndtparam=audio=off\n'
assert effective(f['proposed'](existing))[1] == ['vc4-kms-v3d-pi4,cma-256']
for bad in (b'include other.txt\n', b'[HDMI:0]\ndtoverlay=vc4-kms-v3d\n', b'dtoverlay=vc4-fkms-v3d\n', b'dtoverlay=vc4-kms-v3d,noaudio\n', b'dtoverlay=vc4-kms-v3d\ndtoverlay=vc4-kms-v3d\n', updated+b'dtparam=audio=off\n', updated.replace(b'disable_fw_kms_setup=1', b'disable_fw_kms_setup=1\narm_freq=1900')):
  try: f['proposed'](bad)
  except f['Refused']: pass
  else: raise AssertionError('ambiguous firmware accepted: '+repr(bad))
config = root/'config.txt'
config.write_bytes(original)
f['apply'](config)
assert config.with_name('config.txt.omarchy-before-kms').read_bytes() == original
written = config.stat().st_mtime_ns
f['apply'](config)
assert config.stat().st_mtime_ns == written
other = root/'other.txt';other.write_bytes(b'[all]\n')
try: f['select_config'](candidates=[config,other])
except f['Refused']: pass
else: raise AssertionError('ambiguous boot paths accepted')
config.write_bytes(b'include another.txt\n')
try: f['apply'](config)
except f['Refused']: pass
else: raise AssertionError('included config changed')
assert config.read_bytes() == b'include another.txt\n'
PY
pass "Pi 4 firmware respects applicability and audio order, refuses ambiguity, and backs up idempotently"

for helper in omarchy-pkg-add omarchy-apply-pi-performance; do
  cat >"$test_tmp/bin/$helper" <<'SH'
#!/bin/bash
touch "$TEST_TMP/package-called"
SH
  chmod +x "$test_tmp/bin/$helper"
done
if OMARCHY_RPI_CONFIG_PATH="$test_tmp/config.txt" OMARCHY_RPI_MODULES_PATH="$test_tmp/modules/pi.conf" \
  "$BASH" -euo pipefail -c 'if source "$1"; then exit 0; else exit 1; fi' bash "$ROOT/install/hardware/raspberry-pi.sh" >"$test_tmp/refused-leaf" 2>&1; then
  fail "hardware leaf ignored firmware include refusal"
fi
[[ ! -e $test_tmp/modules && ! -e $test_tmp/package-called ]] || fail "hardware leaf continued mutations after a firmware refusal"
pass "firmware refusal stops sourced hardware setup before modules or package changes"

mkdir -p "$HOME/.config/foot"
cp "$ROOT/config/foot/foot.ini" "$HOME/.config/foot/foot.ini"
OMARCHY_SETUP_CONTEXT=provision-owner "$BASH" -euo pipefail "$ROOT/install/user/hardware/raspberry-pi.sh"
python3 - <<'PY'
import json,os
from pathlib import Path
h=Path(os.environ['HOME']);s=h/'.local/state/omarchy'
assert (s/'toggles/hypr/no-animations.lua').is_file() and (s/'toggles/background-intros-off').exists()
assert (s/'theme-backgrounds/tokyo-night').read_text().endswith('/0-liftoff.webp\n')
assert json.loads((h/'.config/omarchy/shell.json').read_text())['bar']['background']=='opaque'
assert (h/'.local/share/fonts/paper-mono/PaperMono-Regular.ttf').read_bytes()[:4] == b'\0\1\0\0'
assert 'SIL Open Font License' in (h/'.local/share/fonts/paper-mono/OFL.txt').read_text()
assert 'font=Paper Mono:size=9,JetBrainsMono Nerd Font:size=9' in (h/'.config/foot/foot.ini').read_text()
(s/'toggles/hypr/no-animations.lua').unlink();(s/'toggles/background-intros-off').unlink()
(h/'.config/fontconfig/fonts.conf').write_text('owner font choice\n')
PY
OMARCHY_SETUP_CONTEXT=provision-owner "$BASH" -euo pipefail "$ROOT/install/user/hardware/raspberry-pi.sh"
[[ ! -e $HOME/.local/state/omarchy/toggles/hypr/no-animations.lua && ! -e $HOME/.local/state/omarchy/toggles/background-intros-off && $(<"$HOME/.config/fontconfig/fonts.conf") == 'owner font choice' ]] || fail "later finalization reset owner choices"
mkdir -p "$test_tmp/old/.local/state/omarchy/current"
printf 'owner theme\n' >"$test_tmp/old/.local/state/omarchy/current/theme.name"
HOME="$test_tmp/old" OMARCHY_SETUP_CONTEXT=provision-owner "$BASH" -euo pipefail "$ROOT/install/user/hardware/raspberry-pi.sh"
[[ ! -e $test_tmp/old/.config && ! -e $test_tmp/old/.local/state/omarchy/toggles ]] || fail "existing theme/account was reseeded"
mkdir -p "$test_tmp/custom/.config/fontconfig" "$test_tmp/custom/.config/omarchy" "$test_tmp/custom/.config/foot"
printf 'owner font\n' >"$test_tmp/custom/.config/fontconfig/fonts.conf"
printf '{"bar":{"background":"glassy"},"dock":{"pinned":[]}}\n' >"$test_tmp/custom/.config/omarchy/shell.json"
printf 'font=owner:size=13\n' >"$test_tmp/custom/.config/foot/foot.ini"
HOME="$test_tmp/custom" OMARCHY_SETUP_CONTEXT=provision-owner "$BASH" -euo pipefail "$ROOT/install/user/hardware/raspberry-pi.sh"
[[ $(<"$test_tmp/custom/.config/fontconfig/fonts.conf") == 'owner font' && $(<"$test_tmp/custom/.config/foot/foot.ini") == 'font=owner:size=13' && ! -e $test_tmp/custom/.local/share/fonts ]] || fail "fresh setup replaced an explicit font choice"
grep -F '"background":"glassy"' "$test_tmp/custom/.config/omarchy/shell.json" >/dev/null || fail "fresh setup replaced a custom bar or dock"
HOME="$test_tmp/runtime" OMARCHY_SETUP_CONTEXT=runtime "$BASH" -euo pipefail "$ROOT/install/user/hardware/raspberry-pi.sh"
[[ ! -e $test_tmp/runtime ]] || fail "runtime finalization seeded Pi defaults"
pass "new Pi defaults seed static/reduced-motion/font state once and preserve existing users"

# The direct fresh-install entry point must reach the same fresh-account leaf.
# Keep system setup at its privilege boundary and run the real user defaults.
(
  export HOME="$test_tmp/direct-install" USER=fixture
  mkdir -p "$HOME"
  source "$ROOT/install-rpi4.sh"
  sudo() { :; }
  omarchy-provision-user() {
    [[ $* == --first-install ]] || return 1
    source "$ROOT/install/user/hardware/raspberry-pi.sh"
  }
  run_system_setup
)
[[ -f $test_tmp/direct-install/.local/state/omarchy/toggles/hypr/no-animations.lua &&
  -f $test_tmp/direct-install/.config/fontconfig/fonts.conf ]] || fail "direct first installation skipped the Pi defaults"
pass "direct first installation reaches the fresh Pi user-defaults context"

if command -v lua >/dev/null 2>&1; then
  lua - "$ROOT" <<'LUA'
local root = arg[1]
package.path = root .. '/?.lua;' .. package.path
package.loaded['default.hypr.helpers'] = true
package.loaded['default.hypr.paths'] = { home = '/not-a-home', omarchy_path = root }
for _, pi in ipairs({true, false}) do
  local shadow, opaque, loaded = false, false, 0
  o = { shell_quote = function(s) return s end, shell_succeeds = function() return pi end,
    window = function(_, rule) if rule.opacity then opaque = true end end }
  hl = { env = function(key, value) assert(key == 'AQ_NO_MODIFIERS' and value == '1') end,
    on = function() end, get_config = function() return false end, window_rule = function() end,
    config = function(c) if c.decoration then shadow = c.decoration.shadow.enabled end end,
    plugin = { load = function() loaded = loaded + 1 end, hyprbars = { add_button = function() end } } }
  local real_open = io.open
  io.open = function(path, mode)
    if path == '/usr/lib/omarchy-hyprland-titlebars/titlebars.so' then return {close = function() end} end
    return real_open(path, mode)
  end
  dofile(root .. '/default/hypr/raspberry-pi.lua')
  dofile(root .. '/default/hypr/workspace-modes.lua')
  o.workspace_mode({default = 'floating'})
  assert(shadow == not pi, 'floating mode restored expensive shadows on Pi or changed non-Pi behavior')
  assert(opaque and loaded == 1, 'Pi policy broke floating titlebars/opacity')
  io.open = real_open
end
LUA
  pass "Pi floating mode keeps shadow policy while retaining titlebars and opaque windows"
else
  skip "Pi floating behavior fixture requires lua; parent Linux validation must run it"
fi
