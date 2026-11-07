#!/bin/bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"
require_command python3

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mock_bin=$test_tmp/bin
mkdir -p "$mock_bin" "$test_tmp/packages" "$test_tmp/home/.config/mise"
export TEST_CALLS=$test_tmp/calls
: >"$TEST_CALLS"

# All tool/network entry points refuse eager installation. The real declaration
# helper handles opting out; only the architecture predicates are fixtures.
for command in omarchy-hw-raspberry-pi omarchy-hw-aarch64; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
for command in curl wget npm node; do
  printf '#!/bin/bash\necho "unexpected %s" >>"$TEST_CALLS"\nexit 97\n' "$command" >"$mock_bin/$command"
done
cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
[[ ${MISE_OFFLINE:-} == true && ( $* == reshim || $* == 'reshim --system' ) ]] || {
  echo "unexpected mise $*" >>"$TEST_CALLS"
  exit 97
}
echo "offline mise $*" >>"$TEST_CALLS"
SH
chmod +x "$mock_bin"/*
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_MISE_CONFIG_PATH=$ROOT/etc/mise/conf.d/omarchy-tools.toml
export OMARCHY_NODE_PACKAGE_DIR=$test_tmp/packages
export OMARCHY_NODE_BUNDLE_MANIFEST=$test_tmp/manifest.json

make_bundle() {
  python3 -I - "$test_tmp" "$1" <<'PY'
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile

root, mode = Path(sys.argv[1]), sys.argv[2]
bundle = root / "packages/node-v24.2.0-linux-arm64.tar.gz"
archive_root = "node-v24.2.0-linux-arm64"
if mode == "corrupt":
  bundle.write_bytes(b"not a tar archive")
else:
  with tarfile.open(bundle, "w:gz") as archive:
    header = bytearray(64)
    header[:6] = b"\x7fELF\x02\x01"
    header[18:20] = b"\xb7\x00" if mode != "x86" else b"\x3e\x00"
    for name, data in (("bin/node", header), ("bin/npm", b"npm"), ("bin/npx", b"npx")):
      if mode == "incomplete" and name == "bin/npx":
        continue
      member = tarfile.TarInfo(f"{archive_root}/{name}")
      member.size, member.mode = len(data), 0o755
      archive.addfile(member, io.BytesIO(data))
    if mode == "escape":
      member = tarfile.TarInfo(f"{archive_root}/../../escaped")
      member.size = 1
      archive.addfile(member, io.BytesIO(b"!"))
with bundle.open("rb") as stream:
  digest = hashlib.file_digest(stream, "sha256").hexdigest()
if mode == "checksum":
  digest = "0" * 64
(root / "manifest.json").write_text(json.dumps({"node_bundle": {"filename": bundle.name, "sha256": digest}}))
PY
}

run_setup() {
  HOME="$test_tmp/home" OMARCHY_SETUP_CONTEXT="${1:-provision-owner}" \
    bash -e -c 'source "$1"; source "$2"' bash \
      "$ROOT/install/user/mise-work.sh" "$ROOT/install/user/mise.sh" >"$test_tmp/setup.log" 2>&1
}

# The preload must neither select a version nor change user settings/pins.
printf '[tools]\nnode = "22.9.0"\n[settings]\nexperimental = true\n' >"$test_tmp/home/.config/mise/config.toml"
cp "$test_tmp/home/.config/mise/config.toml" "$test_tmp/config.before"
make_bundle valid
run_setup || fail "offline owner setup preloads the staged runtime" "$(cat "$test_tmp/setup.log")"
install=$test_tmp/home/.local/share/mise/installs/node/24.2.0
[[ -x $install/bin/node && -e $install/bin/npm && -e $install/bin/npx ]] || fail "the verified ARM64 runtime is installed completely"
cmp -s "$test_tmp/config.before" "$test_tmp/home/.config/mise/config.toml" || fail "offline setup preserves explicit Node pins and mise settings"
[[ -d $test_tmp/home/Work/tries ]] || fail "mise setup creates the work directories"
echo keep >"$install/user-sentinel"
# A directory left by a killed unpack must not block a fresh atomic retry.
mkdir "$test_tmp/home/.local/share/mise/installs/node/.omarchy-node-interrupted"
run_setup || fail "offline setup can resume" "$(cat "$test_tmp/setup.log")"
[[ $(<"$install/user-sentinel") == keep ]] || fail "resuming setup preserves an existing install"
rm -rf "$install"
run_setup || fail "an interrupted staging directory cannot block a fresh unpack" "$(cat "$test_tmp/setup.log")"
[[ -x $install/bin/node ]] || fail "setup can finish beside interrupted staging"
! grep -q '^unexpected' "$TEST_CALLS" || fail "offline setup attempts no network or eager mise installation"
grep -Fxq 'offline mise reshim --system' "$TEST_CALLS" && grep -Fxq 'offline mise reshim' "$TEST_CALLS" || fail "offline setup requests both sets of native lazy shims"
pass "offline owner setup preloads ARM64 Node and requests lazy shims without network or config writes"

# A missing or malformed archive is required-setup failure; it cannot create a
# partial version or fall back to an online mise install. Retry after repair.
for mode in missing corrupt checksum incomplete x86 escape; do
  rm -rf "$test_tmp/home/.local/share/mise/installs" "$test_tmp/packages/"*
  if [[ $mode != "missing" ]]; then make_bundle "$mode"; fi
  if run_setup; then fail "$mode Node archive is refused"; fi
  [[ ! -e $install ]] || fail "$mode Node archive leaves no partial install"
  [[ ! -e $test_tmp/home/.local/share/mise/escaped ]] || fail "archive traversal cannot escape staging"
  grep -Fq 'offline Node setup failed:' "$test_tmp/setup.log" || fail "$mode archive failure is explicit and retryable" "$(cat "$test_tmp/setup.log")"
  ! grep -q '^unexpected' "$TEST_CALLS" || fail "$mode archive never falls back to the network"
done
make_bundle valid
run_setup || fail "a repaired archive succeeds on the next attempt" "$(cat "$test_tmp/setup.log")"
pass "missing, corrupt, mismatched, incomplete, wrong-architecture and escaping Node archives fail safely and can be retried"

# Native shims replace eager installs on ordinary user setup. Opting out also
# skips the Pi preload, even when no archive is available.
rm -rf "$test_tmp/home/.local/share/mise/installs" "$test_tmp/packages/"*
printf 'ignored_config_paths = ["%s"]\n' "$OMARCHY_MISE_CONFIG_PATH" >"$test_tmp/home/.config/mise/miserc.toml"
run_setup || fail "an explicit default-tools opt-out is honored" "$(cat "$test_tmp/setup.log")"
[[ ! -e $install ]] || fail "opted-out setup does not preload Node"
rm "$test_tmp/home/.config/mise/miserc.toml"
run_setup runtime || fail "ordinary user setup needs no bundled archive" "$(cat "$test_tmp/setup.log")"
cmp -s "$test_tmp/config.before" "$test_tmp/home/.config/mise/config.toml" || fail "all setup paths preserve the user's mise config"
! grep -q '^unexpected' "$TEST_CALLS" || fail "all setup paths avoid eager tool/network commands"
pass "mise setup respects opt-out and leaves ordinary runtime installs lazy"
