import struct,pathlib,hashlib,subprocess,json
w=pathlib.Path('/work');e=w/'evidence';h=w/'headers/usr/lib/modules/7.3.0-32.1-omarchy/build';c=pathlib.Path('/cache/retained-old32.1-evidence/certs/signing_key.x509')
def sha(b):return hashlib.sha256(b).hexdigest()
def elf_section(f,name):
  b=f.read_bytes();shoff=struct.unpack_from('<Q',b,40)[0];sz,n,si=struct.unpack_from('<HHH',b,58)
  tab=[struct.unpack_from('<IIQQQQIIQQ',b,shoff+i*sz) for i in range(n)];st=tab[si];names=b[st[4]:st[4]+st[5]]
  for t in tab:
    if names[t[0]:].split(b'\0')[0].decode()==name:return b[t[4]:t[4]+t[5]]
  raise ValueError(name)
def verify(f):
  b=f.read_bytes();magic=b'~Module signature appended~\n';assert b.endswith(magic)
  trailer=b[-len(magic)-12:-len(magic)];algo,hash_,ident,sl,kl,pad,siglen=struct.unpack('>BBBBB3sI',trailer)
  assert ident==2 and sl==kl==0
  sigstart=len(b)-len(magic)-12-siglen
  (e/'verify-content').write_bytes(b[:sigstart]);(e/'verify.p7s').write_bytes(b[sigstart:sigstart+siglen])
  subprocess.run(['openssl','cms','-verify','-binary','-inform','DER','-in',str(e/'verify.p7s'),'-content',str(e/'verify-content'),'-certfile',str(e/'trusted.pem'),'-nointern','-noverify','-out','/dev/null'],check=True)
  return dict(signed_sha256=sha(b),pkcs7_sha256=sha(b[sigstart:sigstart+siglen]),content_sha256=sha(b[:sigstart]))
cert=c.read_bytes();subprocess.run(['openssl','x509','-inform','DER','-in',str(c),'-out',str(e/'trusted.pem')],check=True)
sym={s[2]:int(s[0],16) for l in (h/'System.map').read_text().splitlines() if len(s:=l.split())==3}
v=(h/'vmlinux').read_bytes();phoff=struct.unpack_from('<Q',v,32)[0];phsz,phn=struct.unpack_from('<HH',v,54)
def readva(addr,n):
  for i in range(phn):
    t,flags,off,va,pa,fs,ms,align=struct.unpack_from('<IIQQQQQQ',v,phoff+i*phsz)
    if t==1 and va<=addr and addr+n<=va+fs:return v[off+addr-va:off+addr-va+n]
  raise ValueError(hex(addr))
start=sym['__cert_list_start'];size=int.from_bytes(readva(sym['system_certificate_list_size'],8),'little');trusted=readva(start,size)
assert cert in trusted
image=subprocess.check_output(['bsdtar','-xOf','/reviewed/packages/linux-omarchy-7.3-32.1-aarch64.pkg.tar.zst','usr/lib/modules/7.3.0-32.1-omarchy/vmlinuz'])
assert image[start-sym['_text']:start-sym['_text']+size]==trusted
r=dict(cert_sha256=sha(cert),trusted_list_sha256=sha(trusted),trusted_list_size=size,image_certificate_offset=start-sym['_text'],image_trust_match=True,installed=verify(e/'installed.ko'))
# Check real in-tree metadata, not external distilled-base policy.
for label in ('baseline','patched'):
  f=e/(label+'.ko');sect=elf_section(f,'.modinfo');assert b'intree=Y\0' in sect
  subprocess.run(['cp',str(f),str(e/(label+'-signed.ko'))],check=True)
  signed=e/(label+'-signed.ko')
  subprocess.run(['strip','-g',str(signed)],check=True)
  subprocess.run([str(h/'scripts/sign-file'),'sha512','/cache/retained-old32.1-evidence/certs/signing_key.pem',str(c),str(signed)],check=True)
  r[label]=verify(signed)
  subprocess.run(['zstd','-T1','-19','-f',str(signed),'-o',str(e/(label+'.ko.zst'))],check=True)
  r[label]['zstd_sha256']=sha((e/(label+'.ko.zst')).read_bytes())
pathlib.Path('/candidate/logs/signature-proof.json').write_text(json.dumps(r,indent=2)+'\n')
