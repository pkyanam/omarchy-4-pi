import hashlib, json, subprocess
from pathlib import Path
r=Path('/candidate'); out=Path('/evidence'); pkg=out/'raspberrypi-4-pftf-cts-1-1-aarch64.pkg.tar.zst'
def extract(name): return subprocess.check_output(['bsdtar','-xOf',str(pkg),name])
meta=extract('.PKGINFO'); (out/'PKGINFO').write_bytes(meta)
(out/'BUILDINFO').write_bytes(extract('.BUILDINFO'))
(out/'archive-files.txt').write_bytes(subprocess.check_output(['bsdtar','-tvf',str(pkg)]))
lines=meta.decode().splitlines()
for line in ['pkgname = raspberrypi-4-pftf-cts','pkgbase = raspberrypi-4-pftf-cts','pkgver = 1-1','arch = aarch64']: assert line in lines, line
assert [s for s in lines if s.startswith('depend = ')] == ['depend = linux-omarchy=7.3-32.2','depend = raspberrypi-4-support','depend = python','depend = util-linux']
hashes={}
for name in ['media-sync.py','baseline-media.json','config.txt.baseline','config.txt.candidate','10-omarchy-pi4-cts.hook','95-omarchy-pi4-cts.hook','09-omarchy-pi4-cts-remove.hook']:
 if name.endswith('.hook'): dest='usr/share/libalpm/hooks/'+name
 elif name == 'media-sync.py': dest='usr/lib/omarchy/pi4-cts/'+name
 else: dest='usr/share/omarchy/pi4-cts/'+name
 data=extract(dest); assert data == (r/'firmware'/name).read_bytes(), name
 hashes[dest]=hashlib.sha256(data).hexdigest()
data=extract('usr/share/omarchy/pi4-cts/omarchy-pi4-aux-rtscts.dtbo'); (out/'cts.dtbo').write_bytes(data)
assert data == (out/'worktree/src/omarchy-pi4-aux-rtscts.dtbo').read_bytes()
hashes['cts.dtbo']=hashlib.sha256(data).hexdigest()
(out/'payload-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
subprocess.run(['dtc','-I','dtb','-O','dts',str(out/'cts.dtbo'),'-o',str(out/'cts.dts')],check=True)
subprocess.run(['fdtoverlay','-i',str(r/'current.fdt'),'-o',str(out/'cts.fdt'),str(out/'cts.dtbo')],check=True)
subprocess.run(['python',str(r/'verify-fdt.py'),str(r/'current.fdt'),str(out/'cts.fdt')],check=True)
# Both early gates, including unchanged kernel prerequisites, must pass.
for recipe in ['kernel','firmware']:
 subprocess.run(['bash',str(r/'kernel/offline-inputs.sh'),str(r/recipe),'/cache/downloads'],check=True)
print('PASS archive identity, exact runtime dependencies, all packaged source bytes, compiled overlay bytes, captured FDT one-property delta and both offline preflights')
