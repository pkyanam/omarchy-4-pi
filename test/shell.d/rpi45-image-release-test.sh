#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
require_command xz
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export PYTHONDONTWRITEBYTECODE=1
# Two MiB keeps compression/hash/reassembly real while making the release
# threshold small enough to test on either development host.
python3 - "$test_tmp/candidate.img" <<'PY'
import os
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(os.urandom(2 * 1024 * 1024))
PY
xz -T1 -0 --stdout "$test_tmp/candidate.img" >"$test_tmp/candidate.img.xz"
image="$test_tmp/candidate.img.xz"
catalog="$test_tmp/candidate.os-list.json"
"$BASH" "$ROOT/image/generate-imager-catalog.sh" "$image" \
  'https://release.invalid/candidate.img.xz?quoted="value"&slash=\' "$catalog"
"$BASH" "$ROOT/image/validate-imager-catalog.sh" "$catalog" "$test_tmp" >/dev/null
mkdir "$test_tmp/release"
"$BASH" "$ROOT/image/prepare-release-assets.sh" "$image" "$test_tmp/release" >"$test_tmp/direct.log" 2>&1
[[ -f $test_tmp/release/candidate.img.xz && -f $test_tmp/release/os-list.json ]] || fail "direct release stages matching whole image and catalog"
"$BASH" "$ROOT/image/validate-imager-catalog.sh" "$test_tmp/release/os-list.json" "$test_tmp/release" >/dev/null
pass "direct release catalog preserves escaping and matches the actual image size/hash"
printf 'tamper' >>"$test_tmp/release/candidate.img.xz"
if "$BASH" "$ROOT/image/validate-imager-catalog.sh" "$test_tmp/release/os-list.json" "$test_tmp/release" >"$test_tmp/tamper.log" 2>&1; then
  fail "modified release asset must fail catalog validation"
fi
OMARCHY_RELEASE_PART_MIB=1 "$BASH" "$ROOT/image/prepare-release-assets.sh" "$image" "$test_tmp/release" >"$test_tmp/split.log" 2>&1
[[ ! -e $test_tmp/release/candidate.img.xz && ! -e $test_tmp/release/candidate.os-list.json && ! -e $test_tmp/release/os-list.json ]] || fail "split release removes stale whole-image promises"
if "$BASH" "$ROOT/image/validate-imager-catalog.sh" "$catalog" "$test_tmp/release" >"$test_tmp/missing.log" 2>&1; then
  fail "dangling whole-image URL must fail asset validation"
fi
pass "split release cannot publish a catalog for its missing whole image"
cat "$test_tmp/release/candidate.img.xz".part-* >"$test_tmp/reassembled.img.xz"
cmp "$image" "$test_tmp/reassembled.img.xz" || fail "split image reassembles exactly"
"$BASH" "$ROOT/image/generate-local-imager-manifest.sh" "$test_tmp/reassembled.img.xz" "$test_tmp/local.json" >"$test_tmp/local.log" 2>&1
"$BASH" "$ROOT/image/validate-imager-catalog.sh" "$test_tmp/local.json" "$test_tmp" >/dev/null
python3 - "$catalog" "$test_tmp/local.json" "$test_tmp/reassembled.img.xz" <<'PY'
import json
from pathlib import Path
import sys
remote, local = (json.loads(Path(path).read_text())["os_list"][0] for path in sys.argv[1:3])
assert local["url"] == Path(sys.argv[3]).resolve().as_uri()
for field in ("extract_size", "extract_sha256", "image_download_size", "image_download_sha256", "init_format"):
  assert remote[field] == local[field], field
assert local["init_format"] == "rpi-preseed"
PY
pass "reassembled image keeps compressed/extracted integrity and customization through the local catalog flow"

# Docker's /output file URLs must be rebased after archive copy to the Mac.
mkdir "$test_tmp/copied host output"
cp "$image" "$test_tmp/copied host output/candidate.img.xz"
"$BASH" "$ROOT/image/generate-local-imager-manifest.sh" "$image" "$test_tmp/candidate.os-list.json" >/dev/null
cp "$test_tmp/candidate.os-list.json" "$test_tmp/copied host output/candidate.os-list.json"
cp "$test_tmp/candidate.os-list.json" "$test_tmp/copied host output/os-list.json"
if "$BASH" "$ROOT/image/validate-imager-catalog.sh" "$test_tmp/copied host output/os-list.json" "$test_tmp/copied host output" >/dev/null 2>&1; then
  fail "copied container file URL must fail before relocation"
fi
python3 "$ROOT/image/relocate-imager-catalogs.py" "$test_tmp/copied host output"
python3 - "$test_tmp" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1]).resolve()
original = json.loads((root / 'candidate.os-list.json').read_text())
expected = original.copy()
expected['os_list'] = [dict(original['os_list'][0], url=(root / 'copied host output/candidate.img.xz').as_uri())]
for name in ('candidate.os-list.json', 'os-list.json'):
  assert json.loads((root / 'copied host output' / name).read_text()) == expected
PY
printf tamper >>"$test_tmp/copied host output/candidate.img.xz"
if python3 "$ROOT/image/relocate-imager-catalogs.py" "$test_tmp/copied host output" >"$test_tmp/relocate-tamper.log" 2>&1; then
  fail "catalog relocation must reject damaged copies instead of blessing new hashes"
fi
pass "copied Mac catalogs resolve host paths with original integrity and reject copy corruption"
