"""Candidate package firmware transaction, invoked by ALPM. Never discover a disk."""
import hashlib,json,os,pathlib,subprocess,sys
P=pathlib.Path
payload=P('/usr/share/omarchy/pi4-cts')
conf=P('/etc/omarchy/pi4-cts-media.json')
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok, message):
  if not ok: raise SystemExit(message)
require(os.geteuid()==0, 'Root required')
require(len(sys.argv) in (2,3) and sys.argv[1] in ('check','apply','restore'), 'Mode required')
if len(sys.argv)==3:
  require(sys.argv[1]=='check', 'Alternate payload allowed only for read-only first-install preflight')
  payload=P(sys.argv[2])
  require(payload.is_absolute() and payload.resolve()==payload, 'Unsafe extracted payload path')
require(conf.is_file() and not conf.is_symlink() and conf.stat().st_uid==0 and conf.stat().st_mode & 0o022==0, 'Configure root-owned /etc/omarchy/pi4-cts-media.json first')
c=json.loads(conf.read_text()); mount=P(c['mount'])
require(mount.is_absolute() and mount.resolve()==mount and str(mount) not in ('/','/boot','/efi'), 'Use a separate firmware-card mount')
m=json.loads(subprocess.check_output(['/usr/bin/findmnt','--json','--mountpoint',str(mount),'-o','TARGET,FSTYPE,UUID'],text=True))['filesystems']
require(len(m)==1 and m[0]['target']==str(mount) and m[0]['fstype']=='vfat' and m[0]['uuid']==c['uuid'], 'Wrong or unmounted firmware card')
baseline=json.loads((payload/'baseline-media.json').read_text())
for name, expected in baseline.items():
  p=mount/name
  require(not p.is_symlink() and p.resolve().is_relative_to(mount) and p.is_file(), 'Unsafe/missing firmware path: '+name)
  if name!='config.txt': require(digest(p)==expected,'Firmware baseline drift: '+name)
old=(payload/'config.txt.baseline').read_bytes(); new=(payload/'config.txt.candidate').read_bytes()
config=mount/'config.txt'; overlay=mount/'overlays/omarchy-pi4-aux-rtscts.dtbo'
require(config.read_bytes() in (old,new),'Unexpected config.txt; review new baseline')
require(not overlay.is_symlink(), 'Unsafe overlay path')
if overlay.exists(): require(digest(overlay)==digest(payload/overlay.name),'Overlay differs from package')
require(config.read_bytes()!=new or overlay.exists(),'Opt-in configured without overlay')
if sys.argv[1]=='check':
  print('Firmware card identity/baseline checked; no write')
else:
  # A root snapshot cannot restore these writes. Keep an explicit file-level backup.
  backup=P('/var/lib/omarchy/pi4-cts'); backup.mkdir(parents=True,exist_ok=True)
  saved=backup/'config.txt.before'
  if saved.exists(): require(saved.read_bytes()==old,'Prior backup differs')
  else: saved.write_bytes(old)
  def atomic(p,data):
    tmp=p.with_name(p.name+'.omarchy-new')
    require(not tmp.exists() and not tmp.is_symlink(),'Stale temporary file: '+str(tmp))
    with tmp.open('xb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
    os.replace(tmp,p)
  if sys.argv[1]=='apply':
    # Overlay first; power loss before config publication leaves the prior boot working.
    atomic(overlay,(payload/overlay.name).read_bytes()); atomic(config,new)
    require(config.read_bytes()==new and digest(overlay)==digest(payload/overlay.name),'Firmware readback failed')
  else:
    atomic(config,old)
    if overlay.exists(): overlay.unlink()
    require(config.read_bytes()==old,'Restore readback failed')
  os.sync()
  print('Firmware '+sys.argv[1]+' complete; boot/live FDT still requires physical verification')
