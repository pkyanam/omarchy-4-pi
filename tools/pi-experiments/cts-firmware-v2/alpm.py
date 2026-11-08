"""Actual production companion; actual kernel/header archives DB-only with explicit real payload subset.
No full kernel extraction, no synthetic kernel or companion. Mount facts mocked only.
"""
import pathlib,subprocess,shutil,json,hashlib,tarfile,io
P=pathlib.Path;r=P('/work/root');logs=P('/candidate/logs');out=P('/work/output');inp=P('/inputs/stable-4.5')
conf=P('/work/fixture-pacman.conf');conf.write_text('[options]\nArchitecture = aarch64\nSigLevel = Never\nLocalFileSigLevel = Never\n')
def pac(*args,ok=None):
 cmd=['pacman','--config',str(conf),'--root',str(r),'--noconfirm','--disable-sandbox',*map(str,args)]
 p=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);print('$',*cmd,'\nexit',p.returncode,'\n'+p.stdout,flush=True)
 if ok is not None:assert (p.returncode==0)==ok,p.stdout
 return p
f=P('/work/fixture-dependencies.pkg.tar');data='pkgname = cts-test-dependencies\npkgver = 1-1\npkgdesc = isolated test dependency providers only\narch = aarch64\n'
for n in ['coreutils','initramfs','kmod','binutils','raspberrypi-4-support','python','util-linux','glibc','libelf','libgcc','openssl','pahole','xxhash','zlib','zstd']:data+='provides = '+n+'\n'
with tarfile.open(f,'w') as t:
 m=tarfile.TarInfo('.PKGINFO');b=data.encode();m.size=len(b);m.mode=0o644;t.addfile(m,io.BytesIO(b))
pac('-U',f,ok=True)
base=inp/'cts-private-package-set-3211/archives'; k=base/'linux-omarchy-7.3-32.11-aarch64.pkg.tar.zst';h=base/'linux-omarchy-headers-7.3-32.11-aarch64.pkg.tar.zst';fw=out/'raspberrypi-4-pftf-cts-1-2-aarch64.pkg.tar.zst'
for a,pin in [(k,'4c457229efda934ce399e03fc94cf6bc4900448275fe5bbacd3d8bfa02e39f13'),(h,'6fc8159044c8cb81b0336bc3f3c5e05b1c30cede104b2334dc13c00667805a38')]:
 assert hashlib.file_digest(a.open('rb'),'sha256').hexdigest()==pin
pac('-U','--dbonly',k,h,ok=True)
subset={}
for a,paths in [(k,['usr/lib/modules/7.3.0-32.1-omarchy/kernel/drivers/tty/serial/8250/8250_bcm2835aux.ko.zst']),(h,['usr/lib/modules/7.3.0-32.1-omarchy/build/Module.symvers'])]:
 for path in paths:
  b=subprocess.check_output(['bsdtar','-xOf',str(a),path]);d=r/path;d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(b);assert d.read_bytes()==b;subset[path]=hashlib.sha256(b).hexdigest()
# Reset old transaction-test fixtures before actual archive installation.
for p in [r/'usr/share/omarchy/pi4-cts',r/'etc/omarchy',r/'var/lib/omarchy',r/'tmp/media']:
 if p.exists():shutil.rmtree(p)
(r/'etc/omarchy').mkdir();media=r/'tmp/media';media.mkdir()
p=pac('-U',fw,ok=True);assert 'Configure root-owned' in p.stdout and 'Checking the identified' not in p.stdout
pac('-Q','raspberrypi-4-pftf-cts',ok=True);pac('-U',fw,ok=False)
print('PASS first-install posthook failure/pacman0: STOP/NO REBOOT',flush=True)
payload=r/'usr/share/omarchy/pi4-cts';baseline=json.loads((payload/'baseline-media.json').read_text());hits=json.loads(P('/candidate/media-inputs.json').read_text())
for name,digest in baseline.items():
 b=(inp.parent/hits[name]).read_bytes() if name!='RPI_EFI.fd' else (inp/'optimization/cts3211-current-RPI_EFI.fd').read_bytes()
 if name!='RPI_EFI.fd':assert hashlib.sha256(b).hexdigest()==digest,name
 d=media/name;d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(b)
def snapshot():return {str(f.relative_to(media)):hashlib.sha256(f.read_bytes()).hexdigest() for f in media.rglob('*') if f.is_file()}
before=snapshot()
(r/'etc/omarchy/pi4-cts-media.json').write_text(json.dumps({'mount':'/tmp/media','uuid':'TEST-CTS'}))
findmnt=r/'usr/bin/findmnt';findmnt.write_text('#!/usr/bin/python\nprint(\'{"filesystems":[{"target":"/tmp/media","fstype":"vfat","uuid":"TEST-CTS"}]}\')\n');findmnt.chmod(0o755)
def helper(mode):subprocess.run(['chroot',str(r),'/usr/bin/python','-I','/usr/lib/omarchy/pi4-cts/media-sync.py',mode],check=True)
# Actual extracted archive first-install route; all media bytes unchanged.
d=r/'extracted';d.mkdir();subprocess.run(['bsdtar','-xpf',str(fw),'-C',str(d)],check=True)
subprocess.run(['chroot',str(r),'/usr/bin/python','-I','/extracted/usr/lib/omarchy/pi4-cts/media-sync.py','check','/extracted/usr/share/omarchy/pi4-cts'],check=True);assert snapshot()==before
helper('check');pac('-U',fw,ok=True);helper('check')
assert (media/'config.txt').read_bytes()==(payload/'config.txt.candidate').read_bytes()
assert (media/'overlays/omarchy-pi4-aux-rtscts.dtbo').read_bytes()==(payload/'omarchy-pi4-aux-rtscts.dtbo').read_bytes()
assert snapshot()['RPI_EFI.fd']==before['RPI_EFI.fd']
pac('-R','linux-omarchy',ok=False);pac('-R','raspberrypi-4-pftf-cts',ok=False)
# Simulate subsequent firmware variable persistence AFTER apply, not a helper write.
efi=media/'RPI_EFI.fd';b=bytearray(efi.read_bytes());b[0x3b1000]^=1;efi.write_bytes(b);nvhash=hashlib.sha256(b).hexdigest()
helper('restore');helper('remove-check');assert efi.read_bytes()==bytes(b)
expected=before|{'RPI_EFI.fd':nvhash};assert snapshot()==expected
pac('-R','raspberrypi-4-pftf-cts',ok=True)
(logs/'alpm-result.json').write_text(json.dumps(dict(actual_companion=True,actual_kernel_headers_archives_database_only=True,real_payload_subset=subset,NVIDIA_installed=False,synthetic_dependency_providers_only=True,first_install_posthook_failure_pacman0=True,prehook_failed_gate=True,extracted_archive_preflight=True,NV_change_after_apply_restore_removal=True,EFI_readback_preserved=True,mount_facts_mocked=True,physical_FAT_qualified=False),indent=2))
print('PASS actual production companion lifecycle and EFI readback; physical FAT unproven')
