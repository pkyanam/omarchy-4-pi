#!/bin/bash

# Open a local Omarchy image through a catalog manifest so Raspberry Pi Imager
# 2.x offers its normal hostname, account, Wi-Fi, locale, and SSH wizard.

set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly imager_app="${OMARCHY_RPI_IMAGER_APP:-/Applications/Raspberry Pi Imager.app}"

server_pid=""

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n $server_pid ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}

if (( $# != 1 )); then
  echo "Usage: $0 IMAGE.img.xz" >&2
  exit 64
fi

[[ $(uname -s) == "Darwin" ]] || fail "This launcher is for macOS. Use generate-local-imager-manifest.sh on other systems."
[[ -d $imager_app ]] || fail "Install Raspberry Pi Imager 2.x in /Applications first."
command -v curl >/dev/null || fail "curl is required"
command -v python3 >/dev/null || fail "python3 is required"

imager_binary="$imager_app/Contents/MacOS/rpi-imager"
[[ -x $imager_binary ]] || fail "Raspberry Pi Imager executable was not found in $imager_app."
version=$(
  "$imager_binary" --version 2>&1 |
    sed -nE 's/.*Raspberry Pi Imager v([0-9]+([.][0-9]+)*).*/\1/p' |
    tail -n 1
)
[[ -n $version ]] || fail "Could not determine the Raspberry Pi Imager version."
[[ $version =~ ^([0-9]+)[.]([0-9]+)[.]([0-9]+)([.][0-9]+)?$ ]] ||
  fail "Could not parse Raspberry Pi Imager version $version."
major=${BASH_REMATCH[1]}
minor=${BASH_REMATCH[2]}
patch=${BASH_REMATCH[3]}
if ! (( major > 2 || (major == 2 && minor > 0) || (major == 2 && minor == 0 && patch >= 11) )); then
  fail "Raspberry Pi Imager 2.0.11 or newer is required for rpi-preseed; found $version. Update Imager, then retry."
fi

image="$1"
image_dir=$(cd -- "$(dirname -- "$image")" && pwd -P)
image="$image_dir/$(basename -- "$image")"
manifest="${image%.img.xz}.imager.json"
port=${OMARCHY_RPI_IMAGER_PORT:-}
if [[ -z $port ]]; then
  port=$(python3 - <<'PY'
import socket

with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    print(listener.getsockname()[1])
PY
  )
fi
[[ $port =~ ^[0-9]+$ ]] && (( port >= 1024 && port <= 65535 )) ||
  fail "OMARCHY_RPI_IMAGER_PORT must be between 1024 and 65535."
image_name=$(python3 - "$(basename -- "$image")" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1]))
PY
)
manifest_name=$(python3 - "$(basename -- "$manifest")" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1]))
PY
)
base_url="http://127.0.0.1:$port"

printf 'Calculating image hashes for Raspberry Pi Imager...\n'
"$script_dir/generate-imager-catalog.sh" "$image" "$base_url/$image_name" "$manifest"

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$image_dir" \
  >/dev/null 2>&1 &
server_pid=$!
trap cleanup EXIT HUP INT TERM
for attempt in {1..40}; do
  if curl --fail --silent --output /dev/null "$base_url/$manifest_name"; then
    break
  fi
  (( attempt < 40 )) || fail "The local image server did not start."
  sleep 0.1
done

printf '\nOpening Raspberry Pi Imager %s. Select Omarchy 4 Pi, then configure the account, Wi-Fi, and SSH before writing.\n' "$version"
printf 'Keep this terminal open until Imager finishes writing. The image server is loopback-only: %s\n' "$base_url"
open -W -n -a "$imager_app" --args --repo "$base_url/$manifest_name"
