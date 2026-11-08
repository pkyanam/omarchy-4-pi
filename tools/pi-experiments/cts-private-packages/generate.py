import pathlib,subprocess,hashlib,json,shutil
p=pathlib.Path('/work/recipes');p.mkdir(exist_ok=True);root=pathlib.Path('/inputs/stable-4.5');review=root/'kernel-reviewed/packages'
prov='Incremental full-payload private candidate 7.3-32.11; release 7.3.0-32.1-omarchy. Authenticated baseline payload retained, only AUX replaced by reviewed signed CTS module. Not a whole kernel recompile or full32.2 rebuild. Exact original compiler command history unknown; documented debug compression difference remains. Controlled parent baseline-equivalence acceptance only. Physical recovery/FDT/radio gates pending.\n'
pins={}
for f in review.glob('*.pkg.tar.zst'):
 meta={}
 for l in subprocess.check_output(['bsdtar','-xOf',str(f),'.PKGINFO'],text=True).splitlines():
  if ' = ' in l:
   k,v=l.split(' = ',1);meta.setdefault(k,[]).append(v)
 name=meta['pkgname'][0];d=p/name;d.mkdir(exist_ok=True)
 (d/'base.pkg.tar.zst').symlink_to(f.resolve())
 sha=hashlib.file_digest(f.open('rb'),'sha256').hexdigest();pins[f.name]=sha
 (d/'provenance.txt').write_text(prov)
 sources=['base.pkg.tar.zst','provenance.txt'];sums=[sha,hashlib.sha256(prov.encode()).hexdigest()]
 if name=='linux-omarchy':
  mod=root/'cts-intree-candidate/modules/patched.ko.zst';(d/'patched.ko.zst').symlink_to(mod.resolve());sources+=['patched.ko.zst'];sums+=['db5cd638b0e88a6b957e50474b7de97ac9bb6f595af8c7e058539cfa8c799993']
 def arr(k,vs):return k+'=('+ ' '.join("'"+v.replace("'", "'\\''")+"'" for v in vs)+')\n'
 text="pkgbase="+name+"-cts-private\npkgname=('"+name+"')\npkgver=7.3\npkgrel=32.11\nurl='https://omarchy.org'\n"+arr('arch',['aarch64'])+arr('license',meta['license'])+arr('makedepends',['libarchive','zstd','python','kmod','openssl','binutils'])+arr('options',['!strip','!debug','!purge','!zipman','!libtool','staticlibs','emptydirs'])+arr('source',sources)+arr('noextract',sources)+arr('sha256sums',sums)
 text+='package_'+name+'() {\n'
 text+="  pkgdesc='"+meta['pkgdesc'][0]+" (incremental full-payload private CTS candidate)'\n"
 for k,out in [('depend','depends'),('optdepend','optdepends'),('provides','provides'),('conflict','conflicts'),('replaces','replaces')]:
  if k in meta:text+='  '+arr(out,[v.replace('linux-omarchy=7.3-32.1','linux-omarchy=7.3-32.11') for v in meta[k]])
 text+='  bsdtar -xpf "$srcdir/base.pkg.tar.zst" -C "$pkgdir" --exclude ".PKGINFO" --exclude ".BUILDINFO" --exclude ".MTREE"\n'
 if name=='linux-omarchy':text+='  cat "$srcdir/patched.ko.zst" > "$pkgdir/usr/lib/modules/7.3.0-32.1-omarchy/kernel/drivers/tty/serial/8250/8250_bcm2835aux.ko.zst"\n'
 text+='  install -Dm644 "$srcdir/provenance.txt" "$pkgdir/usr/share/doc/'+name+'/cts-private-provenance.txt"\n}\n'
 (d/'PKGBUILD').write_text(text)
d=p/'firmware';shutil.copytree(root/'cts-kernel-candidate/firmware',d)
f=d/'PKGBUILD';f.write_text(f.read_text().replace('pkgrel=1\n','pkgrel=1.1\n').replace('linux-omarchy=7.3-32.2','linux-omarchy=7.3-32.11'))
(pathlib.Path('/candidate/logs/base-pins.json')).write_text(json.dumps(pins,indent=2))
