#!/bin/bash

# Root-owned checkpoints for a fresh Pi installation. Never source receipt data.
set -euo pipefail

(( EUID == 0 )) || { echo "Pi installation checkpoints require root." >&2; exit 1; }
operation=${1:?Missing checkpoint operation}
identity=${2:?Missing installation identity}
state_dir=${3:-/var/lib/omarchy/rpi4-install}
[[ $identity =~ ^[0-9a-f]{64}$ && $state_dir == /* ]] || exit 1

fail() { echo "Invalid Pi installation checkpoint: $*" >&2; exit 1; }

validate_state() {
  [[ -d $state_dir && ! -L $state_dir && $(realpath "$state_dir") == "$state_dir" ]] || fail "unsafe directory"
  [[ $(stat -c '%u:%a' "$state_dir") == "0:700" ]] || fail "unsafe directory ownership or permissions"
  local file
  for file in identity phase; do
    [[ -f $state_dir/$file && ! -L $state_dir/$file &&
      $(stat -c '%u:%a:%h' "$state_dir/$file") == "0:600:1" ]] || fail "unsafe $file receipt"
  done
  [[ $(<"$state_dir/identity") =~ ^[0-9a-f]{64}$ ]] || fail "malformed identity"
  phase=$(<"$state_dir/phase")
  case $phase in started|seeded|complete) ;; *) fail "unknown phase" ;; esac
}

write_phase() {
  local temporary
  temporary=$(mktemp "$state_dir/.phase.XXXXXXXX")
  printf '%s\n' "$1" >"$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$state_dir/phase"
}

if [[ -e $state_dir || -L $state_dir ]]; then
  validate_state
else
  phase=missing
fi

case $operation in
  inspect)
    printf '%s\n' "$phase"
    ;;
  begin)
    [[ $phase == "missing" ]] || fail "installation already started"
    parent=$(dirname "$state_dir")
    mkdir -p "$parent"
    [[ $(realpath "$parent") == "$parent" && $(stat -c '%u' "$parent") == "0" ]] || fail "unsafe parent"
    permissions=$(stat -c '%a' "$parent")
    (( (8#$permissions & 0022) == 0 )) || fail "writable parent"
    mkdir -m700 "$state_dir"
    (umask 077; printf '%s\n' "$identity" >"$state_dir/identity")
    write_phase started
    ;;
  resume|seeded|complete)
    [[ $phase != "missing" && $phase != "complete" ]] || fail "no incomplete installation to resume"
    [[ $(<"$state_dir/identity") == "$identity" ]] || fail "source, user, home or installation options changed; use the original checkout and flags"
    if [[ $operation == "resume" ]]; then
      printf '%s\n' "$phase"
    else
      write_phase "$operation"
    fi
    ;;
  *) fail "unknown operation" ;;
esac
