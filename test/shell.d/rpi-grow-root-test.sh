#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/dispatch" <<'MOCK'
#!/bin/bash
set -euo pipefail
command_name=${0##*/}
case "$command_name" in
  findmnt) printf '/dev/mmcblk0p2\n' ;;
  realpath) printf '%s\n' "$1" ;;
  lsblk)
    case "$2" in
      PARTN) [[ ${OMARCHY_TEST_LSBLK_EMPTY:-0} == 1 ]] || printf '2\n' ;;
      PKNAME) [[ ${OMARCHY_TEST_LSBLK_EMPTY:-0} == 1 ]] || printf 'mmcblk0\n' ;;
      *) exit 64 ;;
    esac
    ;;
  growpart)
    printf 'growpart %s %s\n' "$1" "$2" >>"$OMARCHY_TEST_CALLS"
    exit "${OMARCHY_TEST_GROWPART_STATUS:-0}"
    ;;
  udevadm) printf 'udevadm %s\n' "$*" >>"$OMARCHY_TEST_CALLS" ;;
  resize2fs) printf 'resize2fs %s\n' "$1" >>"$OMARCHY_TEST_CALLS" ;;
  systemctl) printf 'systemctl %s\n' "$*" >>"$OMARCHY_TEST_CALLS" ;;
  *) exit 64 ;;
esac
MOCK
chmod +x "$mock_bin/dispatch"
for command_name in findmnt realpath lsblk growpart udevadm resize2fs systemctl; do
  ln -s dispatch "$mock_bin/$command_name"
done

prepare_case() {
  local name="$1"
  case_dir="$test_tmp/$name"
  marker="$case_dir/grow-root-pending"
  unit_link="$case_dir/omarchy-rpi4-grow-root.service"
  calls="$case_dir/calls"
  mkdir -p "$case_dir"
  touch "$marker" "$unit_link" "$calls"
}

run_grow() {
  env \
    PATH="$mock_bin:/usr/bin:/bin" \
    OMARCHY_RPI4_GROW_MARKER="$marker" \
    OMARCHY_RPI4_GROW_UNIT_LINK="$unit_link" \
    OMARCHY_TEST_CALLS="$calls" \
    OMARCHY_TEST_GROWPART_STATUS="${1:-0}" \
    OMARCHY_TEST_LSBLK_EMPTY="${2:-0}" \
    "$ROOT/bin/omarchy-rpi4-grow-root"
}

expected_success=$'growpart /dev/mmcblk0 2\nudevadm settle\nresize2fs /dev/mmcblk0p2\nsystemctl daemon-reload'

prepare_case grown
run_grow 0 >/dev/null
[[ ! -e $marker && ! -e $unit_link ]] || fail "successful root growth disarms its retry state"
[[ $(<"$calls") == "$expected_success" ]] || fail "root growth resizes the discovered Pi partition in order"
pass "successful Pi root growth resizes storage and disarms retry"

prepare_case already_full
run_grow 1 >/dev/null
[[ ! -e $marker && ! -e $unit_link ]] || fail "already-full storage disarms its retry state"
[[ $(<"$calls") == "$expected_success" ]] || fail "already-full storage still verifies the ext4 size"
pass "already-full Pi storage still verifies ext4 before disarming"

prepare_case grow_failed
status=0
run_grow 2 >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "hard growpart failure is propagated"
[[ -e $marker && -e $unit_link ]] || fail "hard growpart failure preserves retry state"
[[ $(<"$calls") == 'growpart /dev/mmcblk0 2' ]] || fail "hard growpart failure stops before filesystem resize"
pass "failed Pi partition growth remains safely armed for retry"

prepare_case metadata_missing
status=0
run_grow 0 1 >/dev/null 2>&1 || status=$?
[[ $status == 1 ]] || fail "missing partition metadata fails root growth"
[[ -e $marker && -e $unit_link ]] || fail "missing partition metadata preserves retry state"
[[ ! -s $calls ]] || fail "missing partition metadata never invokes growpart"
pass "unidentified Pi root storage remains safely armed for retry"

prepare_case not_armed
rm -f "$marker"
run_grow 0 >/dev/null
[[ ! -s $calls ]] || fail "disarmed root growth performs no storage operations"
pass "disarmed Pi root growth is a no-op"
