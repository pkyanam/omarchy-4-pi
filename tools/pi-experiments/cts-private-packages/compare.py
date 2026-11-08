import subprocess,tarfile,hashlib,pathlib,json,sys,gzip
p=pathlib.Path('/candidate');name=sys.argv[1];new=pathlib.Path(sys.argv[2]);old=pathlib.Path('/inputs/stable-4.5/kernel-reviewed/packages')/(name+'-7.3-32.1-aarch64.pkg.tar.zst')
meta={'.PKGINFO','.BUILDINFO','.MTREE'}
def manifest(f):
 z=subprocess.Popen(['zstd','-dc',str(f)],stdout=subprocess.PIPE);d={}
 with tarfile.open(fileobj=z.stdout,mode='r|') as t:
  for m in t:
   n=m.name.removeprefix('./').rstrip('/');assert n not in d,n
   b=t.extractfile(m) if m.isfile() else None
   digest=hashlib.file_digest(b,'sha256').hexdigest() if b else None
   assert m.uid==0 and m.gid in (0,5,11,50),(n,m.uid,m.gid)
   assert not any('capability' in k.lower() for k in m.pax_headers),m.pax_headers
   d[n]=[m.type.decode(),m.mode,m.uid,m.gid,m.linkname,digest,m.pax_headers]
 assert z.wait()==0
 return d
a=manifest(old);b=manifest(new)
prov='usr/share/doc/'+name+'/cts-private-provenance.txt';added=set(b)-set(a)
assert added <= {prov,'usr/share','usr/share/doc','usr/share/doc/'+name},added
for n in added:
 if n!=prov: assert b[n][:5]==['5',0o755,0,0,''],(n,b[n])
assert not set(a)-set(b)
aux='usr/lib/modules/7.3.0-32.1-omarchy/kernel/drivers/tty/serial/8250/8250_bcm2835aux.ko.zst'
changed=[]
for n in a:
 if a[n]!=b[n]:
  changed.append(n)
  if n==aux and name=='linux-omarchy':
   assert a[n][:5]==b[n][:5] and a[n][6]==b[n][6]
   assert b[n][5]=='db5cd638b0e88a6b957e50474b7de97ac9bb6f595af8c7e058539cfa8c799993'
  else:assert n in meta,(n,a[n],b[n])
assert meta <= b.keys()
if name=='linux-omarchy':assert aux in changed
r=dict(old_paths=len(a),new_paths=len(b),changed=changed,added=sorted(added),all_payload_bytes_modes_links_uid_gid_pax_equal_except_aux=True)
(p/'logs'/f'{name}-comparison.json').write_text(json.dumps(r,indent=2))
(p/'logs'/f'{name}-old-manifest.json').write_text(json.dumps(a))
(p/'logs'/f'{name}-new-manifest.json').write_text(json.dumps(b))
for m in meta:
 raw=subprocess.check_output(['bsdtar','-xOf',str(new),m]);(p/'logs'/f'{name}{m}').write_bytes(raw)
print(json.dumps(r),flush=True)
