import pathlib,subprocess,struct,json,hashlib
w=pathlib.Path('/work');e=w/'evidence';p=pathlib.Path('/candidate');h=w/'headers/usr/lib/modules/7.3.0-32.1-omarchy/build'
def sections(f):
  b=f.read_bytes();off=struct.unpack_from('<Q',b,40)[0];sz,n,si=struct.unpack_from('<HHH',b,58)
  tab=[struct.unpack_from('<IIQQQQIIQQ',b,off+i*sz) for i in range(n)];st=tab[si];names=b[st[4]:st[4]+st[5]]
  return {names[t[0]:].split(b'\0')[0].decode():b[t[4]:t[4]+t[5]] for t in tab if t[1]!=8}
a=sections(e/'installed.ko');b=sections(e/'baseline-signed.ko')
names=['.text','.init.text','.exit.text','.modinfo','__versions','__version_ext_crcs','__version_ext_names','.BTF']
r={n:dict(equal=a[n]==b[n],old_sha256=hashlib.sha256(a[n]).hexdigest(),new_sha256=hashlib.sha256(b[n]).hexdigest()) for n in names}
(p/'logs/baseline-section-comparison.json').write_text(json.dumps(r,indent=2)+'\n')
# Export public diagnostic modules only; all full case-sensitive trees stay in Linux.
(p/'modules').mkdir(exist_ok=True)
for f in ('installed.ko','baseline.ko','patched.ko','baseline-signed.ko','patched-signed.ko','baseline.ko.zst','patched.ko.zst'):
  subprocess.run(['cp',str(e/f),str(p/'modules'/f)],check=True)
subprocess.run(['du','-sx','-B1','/','/work'],check=True,stdout=(p/'logs/final-linux-du.txt').open('w'))
