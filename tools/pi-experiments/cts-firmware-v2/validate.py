import pathlib,subprocess,hashlib,json,tarfile,gzip,re
P=pathlib.Path;n=P('/candidate');inp=P('/inputs/stable-4.5');f=P('/work/output/raspberrypi-4-pftf-cts-1-2-aarch64.pkg.tar.zst');old=inp/'cts-private-package-set-3211/archives/raspberrypi-4-pftf-cts-1-1.1-aarch64.pkg.tar.zst'
def raw(f,p):return subprocess.check_output(['bsdtar','-xOf',str(f),p])
def manifest(f):
 z=subprocess.Popen(['zstd','-dc',str(f)],stdout=subprocess.PIPE);d={}
 with tarfile.open(fileobj=z.stdout,mode='r|') as t:
  for m in t:
   name=m.name.removeprefix('./').rstrip('/');d[name]=dict(type=m.type.decode(),mode=m.mode,uid=m.uid,gid=m.gid,link=m.linkname,sha256=hashlib.file_digest(t.extractfile(m),'sha256').hexdigest() if m.isfile() else None,pax=m.pax_headers)
 assert z.wait()==0;return d
a=manifest(old);b=manifest(f);added=set(b)-set(a);assert added=={'usr/share/omarchy/pi4-cts/firmware-identity.json'}
assert set(a)<=set(b)
changed=[p for p in a if a[p]!=b[p]];assert set(changed)=={'.PKGINFO','.BUILDINFO','.MTREE','usr/lib/omarchy/pi4-cts/media-sync.py'}
for name in ['media-sync.py','firmware-identity.json','baseline-media.json','config.txt.baseline','config.txt.candidate','omarchy-pi4-aux-rtscts.dtso','10-omarchy-pi4-cts.hook','95-omarchy-pi4-cts.hook','09-omarchy-pi4-cts-remove.hook']:
 if name.endswith('.dtso'):continue
 path=('usr/lib/omarchy/pi4-cts/' if name=='media-sync.py' else 'usr/share/libalpm/hooks/' if name.endswith('.hook') else 'usr/share/omarchy/pi4-cts/')+name
 assert raw(f,path)==(n/'firmware'/name).read_bytes()
 assert b[path]['uid']==b[path]['gid']==0 and b[path]['mode']==0o644
meta=raw(f,'.PKGINFO').decode();assert 'pkgver = 1-2\n' in meta and 'depend = linux-omarchy=7.3-32.11\n' in meta
for name in ['.PKGINFO','.BUILDINFO','.MTREE']:(n/'logs'/('firmware'+name)).write_bytes(raw(f,name))
mt=gzip.decompress(raw(f,'.MTREE')).decode();(n/'logs/firmware-mtree.txt').write_text(mt);defaults={};seen=set()
for l in mt.splitlines():
 if not l or l.startswith('#'):continue
 parts=l.split();attrs=dict(s.split('=',1) for s in parts[1:] if '=' in s)
 if parts[0]=='/set':defaults.update(attrs);continue
 if parts[0]=='/unset':
  for k in parts[1:]:defaults.pop(k,None)
  continue
 path=re.sub(r'\\([0-7]{3})',lambda m:chr(int(m[1],8)),parts[0]).removeprefix('./').rstrip('/')
 if path=='.':continue
 v=b[path];at=defaults|attrs;seen.add(path);assert int(at['uid'])==v['uid'] and int(at['gid'])==v['gid'] and int(at['mode'],8)==v['mode']
 if v['type']=='0':assert at['sha256digest']==v['sha256']
assert set(b)-{'.MTREE'}==seen
for name,m in [('old',a),('new',b)]:(n/'logs'/f'{name}-archive-manifest.json').write_text(json.dumps(m,indent=2))
dt=P('/work/cts.dtbo');dt.write_bytes(raw(f,'usr/share/omarchy/pi4-cts/omarchy-pi4-aux-rtscts.dtbo'));subprocess.run(['fdtoverlay','-i',str(inp/'cts-kernel-candidate/current.fdt'),'-o','/work/cts.fdt',str(dt)],check=True);subprocess.run(['python',str(inp/'cts-kernel-candidate/verify-fdt.py'),str(inp/'cts-kernel-candidate/current.fdt'),'/work/cts.fdt'],check=True)
receipt=dict(archive=f.name,sha256=hashlib.sha256(f.read_bytes()).hexdigest(),bytes=f.stat().st_size,added=sorted(added),changed=changed,source_archive_match=True,all_other_payload_bytes_attrs_equal=True,mtree_verified=True,DT_one_property_delta=True)
(n/'logs/archive-validation.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt,indent=2))
