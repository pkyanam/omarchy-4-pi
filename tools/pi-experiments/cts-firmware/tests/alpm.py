"""Private container ALPM lifecycle fixture; metadata-only dummy kernels/support.
No real kernel packages or FAT acceptance. Actual candidate helper and hooks.
"""
import io
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tarfile

SOURCE = Path('/work/firmware')

def package(name, version, firmware=False):
  data = f'pkgname = {name}\npkgver = {version}\npkgdesc = private lifecycle fixture\nurl = https://invalid.local\nbuilddate = 1\npackager = fixture\nsize = 1\narch = aarch64\nlicense = GPL\n'
  if firmware:
    depends = subprocess.check_output(['/bin/bash', '-c', 'source /work/firmware/PKGBUILD; printf \"depend = %s\\n\" \"${depends[@]}\"'], text=True)
    data += depends
  dest = Path('/tmp') / f'{name}-{version}-aarch64.pkg.tar'
  with tarfile.open(dest, 'w') as tar:
    def add(path, content):
      entry = tarfile.TarInfo(path); entry.size = len(content); entry.mode = 0o644
      tar.addfile(entry, io.BytesIO(content))
    add('.PKGINFO', data.encode())
    if firmware:
      recipe = Path('/tmp/cts-recipe')
      staged = Path('/tmp/cts-package')
      shutil.copytree(SOURCE, recipe)
      (recipe / 'omarchy-pi4-aux-rtscts.dtbo').write_bytes(b'fixture-overlay-payload')
      subprocess.run(['/bin/bash', '-c', 'source ./PKGBUILD; pkgdir=/tmp/cts-package; package'], cwd=recipe, check=True)
      # Actual package() layout; synthetic bytes/hashes only inside private fixture.
      baseline = {name: hashlib.sha256((SOURCE / 'config.txt.baseline').read_bytes() if name == 'config.txt' else ('fixture:' + name).encode()).hexdigest() for name in json.loads((SOURCE / 'baseline-media.json').read_text())}
      (staged / 'usr/share/omarchy/pi4-cts/baseline-media.json').write_text(json.dumps(baseline))
      for p in staged.rglob('*'):
        if p.is_file(): add(str(p.relative_to(staged)), p.read_bytes())
  return str(dest)

def pacman(*args, success=None):
  p = subprocess.run(['/usr/bin/pacman', '--noconfirm', '--disable-sandbox', *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
  print('$ pacman', *args, '\nexit:', p.returncode, '\n' + p.stdout, flush=True)
  if success is not None: assert (p.returncode == 0) == success
  return p

kernel = package('linux-omarchy', '7.3-32.2')
old = package('linux-omarchy', '7.3-32.1')
support = package('raspberrypi-4-support', '1-3')
fw = package('raspberrypi-4-pftf-cts', '1-1', True)
pacman('-U', kernel, support, success=True)
# No hook installed yet, no config; post-hook invokes actual helper and fails.
p = pacman('-U', fw)
assert 'Root required' not in p.stdout
assert 'Configure root-owned' in p.stdout
assert 'Checking the identified' not in p.stdout
pacman('-Q', 'raspberrypi-4-pftf-cts', success=True)
# Nonzero hook does NOT undo package install (pacman itself may return success).
pacman('-U', fw, success=False)
assert not Path('/tmp/cts-media').exists()
print('PASS first install pre-hook absent, failing post-hook leaves package installed: STOP/NO REBOOT')

# Build real files; only findmnt identity facts replaced. No updater stub.
sys.argv = ['transactions.py', str(SOURCE)]
suite = runpy.run_path('/work/firmware-tests/transactions.py', run_name='fixture')
fixture = suite['Transactions'](); fixture.setUp()
findmnt = Path('/usr/bin/findmnt')
findmnt.rename('/usr/bin/findmnt.real')
findmnt.write_text('#!/bin/bash\ncat /tmp/findmnt-fixture.json\n')
findmnt.chmod(0o755)
Path('/tmp/findmnt-fixture.json').write_text(json.dumps(fixture.facts))
pacman('-U', fw, success=True)
assert (suite['MEDIA'] / 'config.txt').read_bytes() == suite['NEW']
pacman('-U', old, success=False)
pacman('-R', 'linux-omarchy', success=False)
pacman('-R', 'raspberrypi-4-pftf-cts', success=False)
pacman('-Q', 'raspberrypi-4-pftf-cts', success=True)
subprocess.run(['/usr/bin/python', '-I', '/usr/lib/omarchy/pi4-cts/media-sync.py', 'restore'], check=True)
assert fixture.snapshot() == fixture.before
pacman('-R', 'raspberrypi-4-pftf-cts', success=True)
pacman('-U', old, success=True)
print('PASS actual ALPM fixture: exact dependency, pre-upgrade abort, guarded removal, explicit real restore, then downgrade; no firmware/FAT/kernel acceptance')
