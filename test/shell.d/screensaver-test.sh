#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command timeout
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export CALL_LOG="$test_tmp/calls" FRAME_LOG="$test_tmp/frames"

cat >"$test_tmp/bin/hyprctl" <<'SH'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALL_LOG"
SH
cat >"$test_tmp/bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$CALL_LOG"
if [[ $* == "-x ttfx" && -s ${FRAME_LOG}.pid ]]; then
  read -r renderer_pid <"${FRAME_LOG}.pid"
  kill "$renderer_pid" 2>/dev/null || true
fi
SH
cat >"$test_tmp/bin/stty" <<'SH'
#!/bin/bash
echo '40 120'
SH
cat >"$test_tmp/bin/jq" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$test_tmp/bin/"*

run_failure() {
  local expected=$1 status=0
  : >"$CALL_LOG"
  # Isolate PATH so the missing-command case cannot use a host-installed ttfx.
  timeout 5 /usr/bin/env PATH="$test_tmp/bin" /bin/bash "$ROOT/bin/omarchy-screensaver" \
    </dev/null >"$test_tmp/output" 2>&1 || status=$?
  (( status == expected )) || fail "renderer exits with $expected" "actual: $status"
  [[ $(grep -c 'Screensaver renderer failed' "$test_tmp/output") == "1" ]] ||
    fail "renderer failure is reported once"
  grep -F 'invisible = false' "$CALL_LOG" >/dev/null || fail "failure restores cursor visibility"
  grep -Fx 'pkill -f [o]rg.omarchy.screensaver' "$CALL_LOG" >/dev/null || fail "failure closes screensaver windows"
}

run_failure 127
[[ $(grep -c 'command not found' "$test_tmp/output") == "1" ]] || fail "missing renderer is attempted only once"
pass "missing renderer exits promptly, restores cursor, and closes windows without a log loop"

cat >"$test_tmp/bin/ttfx" <<'SH'
#!/bin/bash
printf 'frame\n' >>"$FRAME_LOG"
exit 7
SH
chmod +x "$test_tmp/bin/ttfx"
run_failure 7
[[ $(wc -l <"$FRAME_LOG") == 1 ]] || fail "crashed renderer is not restarted"
pass "crashed renderer preserves failure status without restarting"

: >"$FRAME_LOG"
cat >"$test_tmp/bin/ttfx" <<'SH'
#!/bin/bash
if [[ -s $FRAME_LOG ]]; then
  printf 'frame\n' >>"$FRAME_LOG"
  exit 7
else
  printf 'frame\n' >>"$FRAME_LOG"
  exit 0
fi
SH
run_failure 7
[[ $(wc -l <"$FRAME_LOG") == 2 ]] || fail "successful animation advances to the next effect"
pass "completed effects advance; the first failed effect stops the screensaver"

cat >"$test_tmp/bin/ttfx" <<'SH'
#!/bin/bash
printf '%s\n' "$$" >"${FRAME_LOG}.pid"
exec /bin/sleep 3
SH
: >"$CALL_LOG"
{ sleep 0.2; printf 'q'; } | timeout 5 /usr/bin/env PATH="$test_tmp/bin" /bin/bash "$ROOT/bin/omarchy-screensaver" \
  >"$test_tmp/output" 2>&1 || fail "keyboard input dismisses a running renderer"
grep -F 'invisible = false' "$CALL_LOG" >/dev/null || fail "keyboard dismissal restores cursor"
pass "keyboard input still dismisses a running renderer"

# Run the real package-selection function, stubbing only package operations.
eval "$(sed -n '/^install_arm_packages() {$/,/^}$/p' "$ROOT/install-rpi4.sh")"
log() { :; }
pacman() { return 1; }
build_recipe() { printf '%s %s\n' "$1" "$2" >>"$test_tmp/recipes"; }
install_mode=minimal
install_arm_packages
grep -Fx 'ttfx 1' "$test_tmp/recipes" >/dev/null || fail "minimal Pi installs require ttfx"
[[ $(grep -c '^ttfx ' "$test_tmp/recipes") == 1 ]] || fail "ttfx is selected exactly once"
pass "minimal Pi package selection builds ttfx as a required dependency"

grep -F 'require_executable "$root/usr/bin/ttfx"' "$ROOT/image/audit-rpi4-rootfs.sh" >/dev/null ||
  fail "image audit rejects a missing screensaver renderer"
pass "image audit gates the screensaver executable"
