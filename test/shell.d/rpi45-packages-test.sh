#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
require_command bsdtar
require_command sha512sum
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/render" "$test_tmp/target/etc" "$test_tmp/source/.git"
export TEST_TMP=$test_tmp TEST_CALLS="$test_tmp/calls" TEST_CONFIG="$test_tmp/render/pacman.conf"
export PATH="$test_tmp/bin:$PATH"
# Outer guards prevent every accidental host mutation; individual test doubles
# below expose only the argument/data boundary needed by that assertion.
for command in sudo makepkg pacman-key systemctl; do
  printf '#!/bin/bash\nprintf "unexpected host operation: %%s\\n" "$*" >&2\nexit 91\n' >"$test_tmp/bin/$command"
  chmod +x "$test_tmp/bin/$command"
done
cat >"$test_tmp/bin/omarchy-hw-platform" <<'SH'
#!/bin/bash
echo aarch64
SH
cat >"$test_tmp/bin/omarchy-hw-raspberry-pi" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$test_tmp/bin/omarchy-hw-aarch64" <<'SH'
#!/bin/bash
[[ ${TEST_ARCH:-aarch64} == aarch64 ]]
SH
cat >"$test_tmp/bin/pacman-conf" <<'PY'
#!/usr/bin/env python3
import configparser, os, pathlib, sys
p = configparser.ConfigParser(allow_no_value=True, interpolation=None, strict=False)
p.optionxform = str
p.read(os.environ['TEST_CONFIG'])
a = sys.argv[1:]
if a == ['--repo-list']:
    print('\n'.join(s for s in p.sections() if s != 'options'))
else:
    repo = a[1] if a[0] == '--repo' else 'options'
    key = a[-1]
    value = p[repo].get(key, p['options'].get(key, ''))
    if key == 'Server' and not value:
        value = pathlib.Path(os.environ['TEST_TMP'], 'render/mirrorlist').read_text().split('Server = ', 1)[1].strip()
    print(value.replace('$arch', p['options']['Architecture']).replace('$repo', repo), end='\n' if value else '')
PY
cat >"$test_tmp/bin/git" <<'SH'
#!/bin/bash
case "$3" in
  remote) echo "${TEST_ORIGIN:-https://github.com/pkyanam/omarchy-4-pi.git}" ;;
  symbolic-ref) echo "${TEST_BRANCH:-main}" ;;
  rev-parse)
    if [[ $4 == --abbrev-ref ]]; then echo origin/main; else printf '%040d\n' 123; fi ;;
  status) printf '%s' "${TEST_DIRTY:-}" ;;
  *) printf 'git %s\n' "$3" >>"$TEST_CALLS" ;;
esac
SH
cat >"$test_tmp/bin/pacman" <<'SH'
#!/bin/bash
if [[ $1 == -Sp ]]; then
  [[ ${TEST_SOLVER_FAIL:-0} == 0 ]] || { echo 'unsatisfied dependency' >&2; exit 1; }
  [[ ${TEST_PROTECTED_DEP:-0} == 0 ]] || echo 'omarchy/omarchy 4.5.0-3 aarch64'
  exit 0
elif [[ $1 == -Q ]]; then
  if [[ $2 == mise-bin ]]; then
    echo "mise-bin ${TEST_MISE_VERSION:-2026.11.2-1}"
  elif [[ $2 == bluez-utils ]]; then
    echo "bluez-utils ${TEST_BLUEZ_VERSION:-5.87-2}"
  else
    echo "$2 1.0-1"
  fi
else
  printf 'pacman %s\n' "$*" >>"$TEST_CALLS"
  exit "${TEST_INSTALL_STATUS:-0}"
fi
SH
if ! command -v vercmp >/dev/null; then
  cat >"$test_tmp/bin/vercmp" <<'PY'
#!/usr/bin/env python3
import re, sys
a,b = [tuple(int(n) for n in re.findall(r'\d+', v)) for v in sys.argv[1:]]
print((a>b)-(a<b))
PY
fi
chmod +x "$test_tmp/bin/"*

# Run the real resolver against miniature pacman-format archives. The fake
# pacman supplies only its external solver/installed-state boundary; policy,
# Provides matching, version requests and verification are real implementation.
python3 - "$ROOT" <<'PY'
import importlib.util, io, os, pathlib, sys, tarfile
sys.dont_write_bytecode = True
spec=importlib.util.spec_from_file_location('pi_packages', pathlib.Path(sys.argv[1], 'install/helpers/rpi4-packages.py'))
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r=pathlib.Path(os.environ['TEST_TMP'], 'contract'); (r/'install').mkdir(parents=True)
(r/'install/omarchy-base.packages').write_text('nvim\nmise-bin\noptional-app\n')
(r/'install/omarchy-aarch64.packages').write_text('')
(r/'install/omarchy-rpi4-unavailable.packages').write_text('')
(r/'install/omarchy-rpi4.packages').write_text('required mise-bin>=2026.10.11\noptional optional-app\n')
db=r/'db/sync';db.mkdir(parents=True)
for repo in m.REPOS:
    with tarfile.open(db/f'{repo}.db', 'w:gz') as t:
        if repo=='extra':
            data=b'\0' * 32
            info=tarfile.TarInfo('unrelated-broken-1-1/desc'); info.size=len(data); t.addfile(info,io.BytesIO(data))
        packages=[]
        if repo=='omarchy': packages=[('mise-bin','2026.11.2-1','mise')]
        if repo=='extra': packages=[('neovim','1.0-1','nvim')]
        for name,version,provides in packages:
            data=f'%NAME%\n{name}\n\n%VERSION%\n{version}\n\n%ARCH%\naarch64\n\n%PROVIDES%\n{provides}\n\n'.encode()
            info=tarfile.TarInfo(f'{name}-{version}/desc'); info.size=len(data);t.addfile(info,io.BytesIO(data))
p=m.databases(r/'db'); selected=m.plan(r,'minimal',p)
assert {x['NAME'][0] for x in selected}=={'neovim','mise-bin'}
assert m.resolve('nvim',p)['NAME']==['neovim']
try: m.resolve('mise>=2026.10.11',p)
except ValueError: pass
else: raise AssertionError('unversioned Provides met a version constraint')
os.environ['TEST_MISE_VERSION']='2026.9.1-1'
try: m.verify(selected)
except ValueError as e: assert 'mise-bin' in str(e)
else: raise AssertionError('presence-only stale mise verification passed')
os.environ['TEST_MISE_VERSION']='2026.11.2-1';m.verify(selected)
# A successful repository install is insufficient for the affected client.
bluez = [{'NAME': ['bluez-utils'], 'VERSION': ['5.87-2'], 'REPO': 'extra'}]
assert list(m.install_targets(bluez)) == ['extra/bluez-utils=5.87-2']
m.verify(bluez)  # Compatibility with the pre-backport system transaction.
try: m.verify(bluez, require_backports=True)
except ValueError: pass
else: raise AssertionError('unpatched Bluetooth client passed final runtime verification')
os.environ['TEST_BLUEZ_VERSION']='5.87-2.1';m.verify(bluez, require_backports=True)
assert list(m.install_targets(bluez)) == [], 'reconciliation would downgrade the installed backport'
bluez[0]['VERSION']=['5.88-1']
assert list(m.install_targets(bluez)) == ['extra/bluez-utils=5.88-1'], 'backport hid the next signed release'
try: m.verify(bluez)
except ValueError: pass
else: raise AssertionError('old backport hid a newer signed repository version')
os.environ['TEST_BLUEZ_VERSION']='5.88-1';m.verify(bluez)
os.environ.pop('TEST_BLUEZ_VERSION')
# Some stable archives use the package's full spelling without a Provides.
for record in p:
    if record['NAME']==['neovim']: record.pop('PROVIDES')
with (r/'install/omarchy-rpi4.packages').open('a') as f: f.write('map nvim neovim\n')
assert {x['NAME'][0] for x in m.plan(r,'minimal',p)}=={'neovim','mise-bin'}
(r/'install/omarchy-base.packages').write_text('nvim\nmise-bin\nomasnap\n')
try: m.plan(r,'minimal',p)
except ValueError as e: assert 'omasnap' in str(e)
else: raise AssertionError('required runtime silently disappeared')
(r/'install/omarchy-base.packages').write_text('nvim\nmise-bin\n')
for env in ('TEST_SOLVER_FAIL','TEST_PROTECTED_DEP'):
    os.environ[env]='1'
    try: m.plan(r,'minimal',p)
    except ValueError: pass
    else: raise AssertionError('unsafe/unsatisfied solver result passed')
    os.environ.pop(env)
PY
pass "Pi binary resolver handles Provides, rejects stale installed mise, missing runtime and unsafe dependency closure"

OMARCHY_PACMAN_PROFILE=rpi4 "$ROOT/bin/omarchy-apply-pacman" --render stable "$test_tmp/render" "$test_tmp/target"
printf 'OMARCHY_RPI4_SOURCE=%q\nOMARCHY_PACMAN_PROFILE=rpi4\nOMARCHY_RPI4_PACKAGE_POLICY=stable-4.5\n' "$test_tmp/source" >"$test_tmp/profile"
export OMARCHY_RPI4_PROFILE="$test_tmp/profile"
"$ROOT/bin/omarchy-update-rpi4-guard"
reject() {
  if "$@" >"$test_tmp/rejected" 2>&1; then fail "unsafe Pi operation unexpectedly passed" "$*"; fi
}
for channel in rc edge dev; do
  reject env OMARCHY_PACMAN_PROFILE=rpi4 "$ROOT/bin/omarchy-apply-pacman" --render "$channel" "$test_tmp/render" "$test_tmp/target"
  reject "$ROOT/bin/omarchy-channel-set" "$channel"
done
printf 'OMARCHY_PACMAN_PROFILE=rpi4\n' >"$test_tmp/target/etc/omarchy-rpi4.conf"
reject env OMARCHY_PACMAN_PROFILE=rpi4 "$ROOT/bin/omarchy-apply-pacman" --render stable "$test_tmp/render" "$test_tmp/target"
rm "$test_tmp/target/etc/omarchy-rpi4.conf"
reject env TEST_BRANCH=wrong "$ROOT/bin/omarchy-update-rpi4-guard"
reject env TEST_ORIGIN=https://github.com/omacom/omarchy.git "$ROOT/bin/omarchy-update-rpi4-guard"
reject env TEST_DIRTY=edited "$ROOT/bin/omarchy-update-rpi4-guard"
cp "$TEST_CONFIG" "$test_tmp/good.conf"
sed 's|pkgs.omarchy.org/stable|pkgs.omarchy.org/edge|' "$test_tmp/good.conf" >"$TEST_CONFIG"
reject "$ROOT/bin/omarchy-update-rpi4-guard" packages
cp "$test_tmp/good.conf" "$TEST_CONFIG"
sed 's/SigLevel = Required/SigLevel = Never/' "$test_tmp/good.conf" >"$TEST_CONFIG"
reject "$ROOT/bin/omarchy-update-rpi4-guard" packages
cp "$test_tmp/good.conf" "$TEST_CONFIG"
cp "$test_tmp/profile" "$test_tmp/good.profile"
sed '/OMARCHY_RPI4_PACKAGE_POLICY/d' "$test_tmp/good.profile" >"$test_tmp/profile"
reject "$ROOT/bin/omarchy-update-rpi4-guard"
grep -q 'legacy rolling ALARM profile' "$test_tmp/rejected" || fail "legacy Pi refusal explains reflash recovery"
reject bash -c 'source "$OMARCHY_PATH/install-rpi4.sh"; ensure_package_sources'
grep -q 'Legacy rolling ALARM profile' "$test_tmp/rejected" || fail "old updater sourcing new installer leaves gets recovery guidance"
cp "$test_tmp/good.profile" "$test_tmp/profile"
reject "$ROOT/bin/omarchy-update-rpi4-guard" transaction
OMARCHY_RPI4_CORE_INSTALL=1 "$ROOT/bin/omarchy-update-rpi4-guard" transaction
pass "rendered stable ARM repositories pass; mixed repos, unsafe signatures, legacy cards and upstream channels fail before mutations"

# Integrity failure must precede public key installation and privileged trust.
cat >"$test_tmp/bin/curl" <<'SH'
#!/bin/bash
while (( $# )); do
  if [[ $1 == --output ]]; then printf 'tampered keyring' >"$2"; exit 0; fi
  shift
done
exit 1
SH
chmod +x "$test_tmp/bin/curl"
reject bash -c 'source "$OMARCHY_PATH/install/helpers/pacman.sh"; omarchy_pi_bootstrap_keyring'
[[ ! -e $TEST_CALLS ]] || fail "bad trust input reached a privileged operation"
pass "reviewed public-key bootstrap rejects tampered keyring data before installing trust"

# Exercise actual artifact parsing, including an incomplete set and a stale core.
source "$ROOT/install/helpers/rpi4-packages.sh"
mkdir -p "$test_tmp/artifacts" "$test_tmp/payload"
archive() {
  printf 'pkgname = %s\npkgver = %s\narch = %s\n' "$1" "$2" "$3" >"$test_tmp/payload/.PKGINFO"
  bsdtar -czf "$test_tmp/artifacts/$1.pkg.tar.gz" -C "$test_tmp/payload" .PKGINFO
}
archive omarchy "$omarchy_pi_core_version-1" aarch64
reject omarchy_pi_verify_artifacts "$test_tmp/artifacts"
archive omarchy-settings 4.0.2-1 aarch64
archive omarchy-keyring 20251027-1 any
archive ttf-jetbrains-mono-nerd-basic 3.5.1-2 any
reject omarchy_pi_verify_artifacts "$test_tmp/artifacts"
archive omarchy-settings "$omarchy_pi_core_version-1" aarch64
omarchy_pi_verify_artifacts "$test_tmp/artifacts"
cp "$test_tmp/artifacts/omarchy.pkg.tar.gz" "$test_tmp/artifacts/unrelated-stale.pkg.tar.gz"
printf '%s.pkg.tar.gz\n' "${omarchy_pi_core_packages[@]}" >"$test_tmp/artifacts/omarchy-pi-artifacts.list"
omarchy_pi_verify_artifacts "$test_tmp/artifacts"
[[ " ${omarchy_pi_artifacts[*]} " != *unrelated-stale* ]] || fail "unlisted stale artifact reached installation"
printf '../outside.pkg.tar.gz\n' >"$test_tmp/artifacts/omarchy-pi-artifacts.list"
reject omarchy_pi_verify_artifacts "$test_tmp/artifacts"
pass "only a complete matching-version Pi core artifact set can reach installation"
