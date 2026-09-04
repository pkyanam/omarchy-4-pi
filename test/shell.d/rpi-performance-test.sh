#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/proc/device-tree" "$test_tmp/sys"
cat >"$test_tmp/bin/omarchy-hw-raspberry-pi" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$test_tmp/bin/nproc" <<'SH'
#!/bin/bash
echo 4
SH
cat >"$test_tmp/bin/systemd-run" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$CALL_LOG"
exit "${SCOPE_STATUS:-0}"
SH
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$PATH" CALL_LOG="$test_tmp/calls"
export OMARCHY_PI_MEMINFO="$test_tmp/proc/meminfo"
printf 'MemTotal: 4000000 kB\nMemAvailable: 2500000 kB\n' >"$OMARCHY_PI_MEMINFO"
"$ROOT/bin/omarchy-pi-run" --plan -- bash >"$test_tmp/plan"
[[ ! -e $CALL_LOG ]] || fail "plan must not create a scope"
grep -F 'MAKEFLAGS=-j2' "$test_tmp/plan" >/dev/null || fail "available RAM limits build parallelism"
pass "workload preview is read-only and RAM-aware"
"$ROOT/bin/omarchy-pi-run" -- printf '%s' 'argument with spaces; no shell evaluation'
grep -Fx 'CPUQuota=300%' "$CALL_LOG" >/dev/null || fail "Pi workload leaves one CPU-equivalent for the desktop"
grep -Fx 'MemoryHigh=50%' "$CALL_LOG" >/dev/null || fail "scope sets memory reclaim threshold"
grep -Fx 'MemoryMax=65%' "$CALL_LOG" >/dev/null || fail "scope sets final memory ceiling"
grep -Fx -- '--expand-environment=no' "$CALL_LOG" >/dev/null || fail "systemd must not expand dollar signs in agent prompts"
grep -Fx 'argument with spaces; no shell evaluation' "$CALL_LOG" >/dev/null || fail "workload argv is preserved"
status=0
SCOPE_STATUS=9 "$ROOT/bin/omarchy-pi-run" -- true || status=$?
(( status == 9 )) || fail "scope failure must not fall back to unrestricted execution"
pass "workload limits, literal argv, and scope failure propagation"

printf 'Raspberry Pi 4 Model B Rev 1.5\0' >"$test_tmp/proc/device-tree/model"
export OMARCHY_PI_PROC_ROOT="$test_tmp/proc" OMARCHY_PI_SYS_ROOT="$test_tmp/sys"
"$ROOT/bin/omarchy-pi-report" --json >"$test_tmp/report"
jq -e '.schema == 1 and .memory_kib.total == 4000000 and .temperature_c == null and .pressure.cpu == null and .cpu_policies == []' "$test_tmp/report" >/dev/null || fail "report preserves unknown sensors as null"
mkdir -p "$test_tmp/sys/class/thermal/thermal_zone0" "$test_tmp/sys/class/hwmon/hwmon0" "$test_tmp/proc/pressure"
printf 'cpu-thermal\n' >"$test_tmp/sys/class/thermal/thermal_zone0/type"
printf '43800\n' >"$test_tmp/sys/class/thermal/thermal_zone0/temp"
printf 'rpi_volt\n' >"$test_tmp/sys/class/hwmon/hwmon0/name"
printf '0\n' >"$test_tmp/sys/class/hwmon/hwmon0/in0_lcrit_alarm"
printf 'some avg10=1.00 avg60=0.50 avg300=0.10 total=10\n' >"$test_tmp/proc/pressure/memory"
"$ROOT/bin/omarchy-pi-report" --json >"$test_tmp/report"
jq -e '.temperature_c == 43.8 and .undervoltage_alarm == 0 and (.pressure.memory | contains("avg10=1.00"))' "$test_tmp/report" >/dev/null || fail "report reads native Linux health and pressure sensors"
pass "agent-readable diagnostics handle present and missing native sensors"

mkdir -p "$test_tmp/source/build" "$test_tmp/source/.git" "$test_tmp/source/build-output-rpi4" "$test_tmp/staging"
printf 'payload\n' >"$test_tmp/source/keep"
printf 'large image placeholder\n' >"$test_tmp/source/build/image"
(
  source "$ROOT/build-packages-rpi4.sh"
  # Run the real staging function against a fixture in a separate shell, where
  # its readonly checkout can be substituted without copying the developer tree.
  declare -f prepare_source_tree
) >"$test_tmp/stage-function"
(
  source "$test_tmp/stage-function"
  checkout="$test_tmp/source"
  build_root="$test_tmp/staging"
  prepare_source_tree
)
[[ -f $test_tmp/staging/source/keep && ! -e $test_tmp/staging/source/build && ! -e $test_tmp/staging/source/.git ]] || fail "package staging excludes artifacts and Git metadata"
pass "package staging copies working source without image artifacts or Git history"
