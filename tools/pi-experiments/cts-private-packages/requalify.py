import struct,pathlib,hashlib,subprocess,json
w=pathlib.Path('/intree');e=pathlib.Path('/work/crypto');e.mkdir(exist_ok=True);h=w/'headers/usr/lib/modules/7.3.0-32.1-omarchy/build';c=pathlib.Path('/cache/retained-old32.1-evidence/certs/signing_key.x509')
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
image=subprocess.check_output(['bsdtar','-xOf','/inputs/stable-4.5/kernel-reviewed/packages/linux-omarchy-7.3-32.1-aarch64.pkg.tar.zst','usr/lib/modules/7.3.0-32.1-omarchy/vmlinuz'])
assert image[start-sym['_text']:start-sym['_text']+size]==trusted

assert sha(cert)=='eb0a0ff4acefb1182818c8a33de6e03fb96c6fb826cefa92cec3baf5d18a7d05'
f=pathlib.Path('/inputs/stable-4.5/cts-intree-candidate/modules/patched.ko.zst')
assert sha(f.read_bytes())=='db5cd638b0e88a6b957e50474b7de97ac9bb6f595af8c7e058539cfa8c799993'
mod=e/'patched.ko';mod.write_bytes(subprocess.check_output(['zstd','-dc',str(f)]))
assert sha(mod.read_bytes())=='72cfc483aacd7879b0e676e93f854d345a9235ffab56a9f3516d5fe96e1f7347'
r=verify(mod)
receipt=json.loads(pathlib.Path('/inputs/stable-4.5/cts-intree-candidate/logs/signature-proof.json').read_text())
assert all(r[k]==receipt['patched'][k] for k in r)
info=subprocess.check_output(['modinfo',str(mod)],text=True);print(info)
assert 'intree:         Y' in info
assert '7.3.0-32.1-omarchy' in info
assert b'intree=Y\0' in elf_section(mod,'.modinfo')
assert elf_section(mod,'.BTF')==elf_section(pathlib.Path('/intree/evidence/patched.ko'),'.BTF')
vers={s[1]:s[0] for l in subprocess.check_output(['modprobe','--show-modversions',str(mod)],text=True).splitlines() if len(s:=l.split())==2}
sym={s[1]:s[0] for l in (h/'Module.symvers').read_text().splitlines() if len(s:=l.split())>=2}
assert all(sym[k]==v for k,v in vers.items())
config=(h/'.config').read_bytes();assert sha(config)=='3b12d3dd8d8b0b24ab95ef96bb1b3388d2440a5bda069ecd74f3c7984a2fd51d'
a=pathlib.Path('/intree/evidence/installed.ko');b=pathlib.Path('/intree/evidence/baseline-signed.ko')
for section in ['.text','.init.text','.exit.text','.modinfo','__versions','__version_ext_crcs','__version_ext_names','.BTF']:assert elf_section(a,section)==elf_section(b,section),section
# Every command flag below must have a matching enabled config and real Kbuild rule.
cmd=pathlib.Path('/inputs/stable-4.5/cts-intree-candidate/logs/patched.o.cmd').read_text().split('\n')[0]
checks=[('STACKPROTECTOR_STRONG','-fstack-protector-strong','Makefile'),('INIT_STACK_ALL_ZERO','-ftrivial-auto-var-init=zero','Makefile'),('SHADOW_CALL_STACK','-fsanitize=shadow-call-stack','Makefile'),('ZERO_CALL_USED_REGS','-fzero-call-used-regs=used-gpr','Makefile'),('ARM64_PTR_AUTH_KERNEL','-mbranch-protection=pac-ret','arch/arm64/Makefile'),('UBSAN_BOUNDS','-fsanitize=bounds-strict','scripts/Makefile.ubsan')]
proof=[]
for cfg,flag,file in checks:
 assert ('CONFIG_'+cfg+'=y').encode() in config,cfg
 assert flag in cmd,flag
 source=pathlib.Path('/intree/linux-7.3')/file;lines=source.read_text().splitlines();matches=[(i+1,l) for i,l in enumerate(lines) if flag in l]
 assert matches,(file,flag)
 proof.append(dict(config=cfg,flag=flag,source=file,sha256=sha(source.read_bytes()),rules=matches))
pathlib.Path('/candidate/logs/requalification.json').write_text(json.dumps(dict(crypto=r,trusted_certificate_sha256=sha(cert),kernel_image_trust=True,CRCs=vers,hardening=proof,baseline_sections_equal=True),indent=2))
