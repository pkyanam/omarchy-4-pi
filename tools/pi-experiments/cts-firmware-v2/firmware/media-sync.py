"""Candidate package firmware transaction, invoked by ALPM. Never discover a disk."""
import hashlib,json,os,pathlib,subprocess,sys
P=pathlib.Path
payload=P('/usr/share/omarchy/pi4-cts')
conf=P('/etc/omarchy/pi4-cts-media.json')
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok, message):
  if not ok: raise SystemExit(message)
require(os.geteuid()==0, 'Root required')
require(len(sys.argv) in (2,3) and sys.argv[1] in ('check','apply','restore','remove-check'), 'Mode required')
if len(sys.argv)==3:
  require(sys.argv[1]=='check', 'Alternate payload allowed only for read-only first-install preflight')
  payload=P(sys.argv[2])
  require(payload.is_absolute() and payload.resolve()==payload, 'Unsafe extracted payload path')
require(conf.resolve()==conf, 'Unsafe media configuration path')
require(conf.is_file() and not conf.is_symlink() and conf.stat().st_uid==0 and conf.stat().st_mode & 0o022==0, 'Configure root-owned /etc/omarchy/pi4-cts-media.json first')
c=json.loads(conf.read_text()); mount=P(c['mount'])
require(mount.is_absolute() and mount.resolve()==mount and str(mount) not in ('/','/boot','/efi'), 'Use a separate firmware-card mount')
m=json.loads(subprocess.check_output(['/usr/bin/findmnt','--json','--mountpoint',str(mount),'-o','TARGET,FSTYPE,UUID'],text=True))['filesystems']
require(len(m)==1 and m[0]['target']==str(mount) and m[0]['fstype']=='vfat' and m[0]['uuid']==c['uuid'], 'Wrong or unmounted firmware card')
baseline=json.loads((payload/'baseline-media.json').read_text())
for name, expected in baseline.items():
  p=mount/name
  require(not p.is_symlink() and p.resolve()==p and p.is_relative_to(mount) and p.is_file(), 'Unsafe/missing firmware path: '+name)
  if name=='RPI_EFI.fd':
    identity=payload/'firmware-identity.json'
    require(identity.resolve()==identity and identity.is_file() and identity.stat().st_uid==0 and identity.stat().st_mode & 0o022==0, 'Unsafe firmware identity manifest')
    ident=json.loads(identity.read_text())
    require(ident['schema']==1 and ident['route']=='private-reviewed-PFTF-RPi4-1.53', 'Unknown firmware identity route')
    data=p.read_bytes()
    require(len(data)==ident['size']==0x3d0000, 'Firmware identity length mismatch')
    spans=[(0,0x20000),(0x20000,0x3b0000),(0x3b0000,0x3b0064),(0x3be000,0x3bf000),(0x3bf000,0x3c0000),(0x3c0000,0x3d0000)]
    require([(r['start'],r['end']) for r in ident['regions']]==spans and ident['mutable']['start']==0x3b0064 and ident['mutable']['end']==0x3be000, 'Invalid firmware identity coverage')
    for r in ident['regions']:
      require(hashlib.sha256(data[r['start']:r['end']]).hexdigest()==r['sha256'], 'Firmware fixed-region drift: '+r['name'])
    # Fixed hashes authenticate FV checksum/block map and the complete store
    # GUID/size/format/health/reserved fields before interpreting any lengths.
    import struct
    fv=0x3b0000
    hlen=struct.unpack_from('<H',data,fv+48)[0]
    require(hlen==0x48 and hlen+struct.calcsize('<16sIBBHI')==ident['mutable']['start']-fv, 'Malformed firmware header boundary')
    require(sum(struct.unpack_from('<'+str(hlen//2)+'H',data,fv)) & 0xffff==0, 'Malformed FV checksum')
    require(struct.unpack_from('<I',data,fv+hlen+16)[0]==0xe000-hlen, 'Malformed variable store size')
  elif name!='config.txt': require(digest(p)==expected,'Firmware baseline drift: '+name)
old=(payload/'config.txt.baseline').read_bytes(); new=(payload/'config.txt.candidate').read_bytes()
config=mount/'config.txt'; overlay=mount/'overlays/omarchy-pi4-aux-rtscts.dtbo'
require(config.read_bytes() in (old,new),'Unexpected config.txt; review new baseline')
require(not overlay.is_symlink(), 'Unsafe overlay path')
if overlay.exists(): require(digest(overlay)==digest(payload/overlay.name),'Overlay differs from package')
require(config.read_bytes()!=new or overlay.exists(),'Opt-in configured without overlay')
if sys.argv[1]=='remove-check':
  require(config.read_bytes()==old and not overlay.exists(), 'Restore firmware before removing companion; stop/no reboot')
  print('Firmware restored; companion removal allowed')
elif sys.argv[1]=='check':
  print('Firmware card identity/baseline checked; no write')
else:
  # A root snapshot cannot restore these writes. Keep an explicit file-level backup.
  backup=P('/var/lib/omarchy/pi4-cts')
  require(backup.resolve()==backup, 'Unsafe backup directory')
  backup.mkdir(parents=True,exist_ok=True,mode=0o700)
  require(backup.stat().st_uid==0 and backup.stat().st_mode & 0o022==0, 'Unsafe backup permissions')
  # Serialize cooperating invocations; no concurrent card/package maintenance is supported.
  import fcntl
  lockfd=os.open(backup/'transaction.lock',os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
  fcntl.flock(lockfd,fcntl.LOCK_EX|fcntl.LOCK_NB)
  def sync_dir(p):
    fd=os.open(p,os.O_RDONLY|os.O_DIRECTORY)
    try: os.fsync(fd)
    finally: os.close(fd)
  def atomic(p,data):
    tmp=p.with_name(p.name+'.omarchy-new')
    require(not tmp.exists() and not tmp.is_symlink(),'Stale temporary file: '+str(tmp))
    created=False
    try:
      with tmp.open('xb') as f:
        created=True
        f.write(data); f.flush(); os.fsync(f.fileno())
      os.replace(tmp,p)
      sync_dir(p.parent)
    finally:
      # Only remove the temporary file created by this invocation. Pre-existing
      # files (including interrupted-process residue) require operator review.
      if created and tmp.exists(): tmp.unlink()
  saved=backup/'config.txt.before'
  require(saved.resolve()==saved and not saved.is_symlink(), 'Unsafe backup file')
  if saved.exists(): require(saved.read_bytes()==old,'Prior backup differs')
  else: atomic(saved,old)
  try:
    if sys.argv[1]=='apply':
      # Publish and sync overlay namespace, then verify bytes BEFORE config.
      atomic(overlay,(payload/overlay.name).read_bytes())
      require(digest(overlay)==digest(payload/overlay.name),'Overlay readback failed before config publication')
      atomic(config,new)
      require(config.read_bytes()==new,'Firmware config readback failed')
    else:
      atomic(config,old)
      require(config.read_bytes()==old,'Restore readback failed')
      if overlay.exists():
        overlay.unlink()
        sync_dir(overlay.parent)
    os.sync()
    print('Firmware '+sys.argv[1]+' complete; boot/live FDT still requires physical verification')
  except OSError:
    # A failure after rename may already have published the new config. Never
    # claim rollback or reboot safety from an error, especially on FAT.
    print('Firmware I/O failed: STOP; do not reboot; inspect/restore card',file=sys.stderr)
    raise
  finally:
    os.close(lockfd)
