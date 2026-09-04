#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
source "$ROOT/image/inspect-rpios-driver-packages.sh"
mkdir -p "$test_tmp/package/DEBIAN" "$test_tmp/package/usr/lib/firmware" "$test_tmp/bin" "$test_tmp/output"
cat >"$test_tmp/package/DEBIAN/control" <<'EOF'
Package: firmware-fixture
Version: 1
Architecture: all
Maintainer: Test <test@example.invalid>
Description: inspection fixture
EOF
cat >"$test_tmp/package/DEBIAN/postinst" <<'SH'
#!/bin/bash
touch "$PI_MAINTAINER_EXECUTED"
SH
chmod +x "$test_tmp/package/DEBIAN/postinst"
printf 'firmware fixture\n' >"$test_tmp/package/usr/lib/firmware/example.bin"
dpkg-deb --build "$test_tmp/package" "$test_tmp/fixture.deb" >/dev/null
export PI_MAINTAINER_EXECUTED="$test_tmp/unsafe" PI_FIXTURE_DEB="$test_tmp/fixture.deb"
checksum=$(sha256sum "$PI_FIXTURE_DEB" | awk '{print $1}')
output="$test_tmp/output"
printf 'Package: firmware-fixture\nVersion: 1\nFilename: pool/main/f/fixture.deb\nSHA256: %s\n\n' "$checksum" >"$output/Packages"
cat >"$test_tmp/bin/curl" <<'SH'
#!/bin/bash
while (( $# )); do
  if [[ $1 == "-o" ]]; then cp "$PI_FIXTURE_DEB" "$2"; exit; fi
  shift
done
exit 1
SH
chmod +x "$test_tmp/bin/curl"
export PATH="$test_tmp/bin:$PATH"
inspect_package firmware-fixture
[[ -f $output/extracted/firmware-fixture/usr/lib/firmware/example.bin ]] || fail "inspection extracts package data"
[[ -f $output/control/firmware-fixture/postinst && ! -e $PI_MAINTAINER_EXECUTED ]] || fail "inspection must not run maintainer scripts"
pass "verified package inspection extracts data and control files without installation"
printf 'tamper\n' >>"$output/fixture.deb"
if (verify_file "$output/fixture.deb" "$checksum") >/dev/null 2>&1; then fail "inspection accepts corrupted firmware"; fi
if (verify_file "$output/fixture.deb" '') >/dev/null 2>&1; then fail "inspection accepts missing checksums"; fi
pass "firmware inspection rejects checksum mismatches and absent hashes"
