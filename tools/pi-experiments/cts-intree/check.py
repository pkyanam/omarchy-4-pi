import sys,pathlib,hashlib,subprocess,json,tarfile,stat
p=pathlib.Path('/candidate/logs');w=pathlib.Path('/work');h=w/'headers/usr/lib/modules/7.3.0-32.1-omarchy/build'
def digest(f):
  with open(f,'rb') as s:return hashlib.file_digest(s,'sha256').hexdigest()
def cmd(*a):return subprocess.check_output(a,text=True)
def save(n,r): (p/n).write_text(json.dumps(r,indent=2)+'\n')
if sys.argv[1]=='inputs':
  pins={'linux-omarchy-7.3-32.1-aarch64.pkg.tar.zst':'2164fb79c02442b9047166b07f1667558f1674c2ccf345d38b9f7e10e97ef8d8','linux-omarchy-headers-7.3-32.1-aarch64.pkg.tar.zst':'1c90e860325eed52865869c060f762718784f9bda9cc9d7978fa636ce74f89e1','linux-omarchy-nvidia-open-7.3-32.1-aarch64.pkg.tar.zst':'4d76415647b2a9c1cbf91293bdebf51da47193ed6ab49320ed8ead7baa69386f'}
  for f,x in pins.items():assert digest('/reviewed/packages/'+f)==x
  assert digest('/inputs/linux-7.3.tar.xz')=='87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953'
  save('input-pins.json',pins)
elif sys.argv[1]=='headers':
  r=[];bad=[];special=0
  z=subprocess.Popen(['zstd','-dc','/reviewed/packages/linux-omarchy-headers-7.3-32.1-aarch64.pkg.tar.zst'],stdout=subprocess.PIPE)
  with tarfile.open(fileobj=z.stdout,mode='r|') as t:
    for m in t:
      f=w/'headers'/m.name
      s=f.lstat();errors=[]
      if stat.S_IMODE(s.st_mode)!=m.mode:errors.append('mode')
      if m.isfile():
        x=hashlib.sha256(t.extractfile(m).read()).hexdigest()
        if digest(f)!=x:errors.append('bytes')
        r.append([m.name,x,m.mode])
        rel=m.name.split('/build/',1)[-1]
        if '/build/' in m.name and (rel.endswith('.h') or rel in ('.config','Module.symvers','System.map','vmlinux','include/config/kernel.release')):special+=1
      elif m.issym():
        if not f.is_symlink() or str(f.readlink())!=m.linkname:errors.append('link')
      elif m.isdir():
        if not f.is_dir():errors.append('directory')
      elif m.islnk():
        if not f.samefile(w/'headers'/m.linkname):errors.append('hardlink')
      else:errors.append('unsupported-type')
      if errors:bad.append([m.name,errors])
  assert z.wait()==0
  save('headers-manifest.json',r);save('headers-audit.json',dict(files=len(r),abi_header_comparisons=special,mismatches=bad))
  assert special==7381 and not bad
  assert digest(h/'.config')=='3b12d3dd8d8b0b24ab95ef96bb1b3388d2440a5bda069ecd74f3c7984a2fd51d'
else:
  label=sys.argv[1]
  if not (w/'evidence/installed.ko').exists():
    z=subprocess.check_output(['bsdtar','-xOf','/reviewed/packages/linux-omarchy-7.3-32.1-aarch64.pkg.tar.zst','usr/lib/modules/7.3.0-32.1-omarchy/kernel/drivers/tty/serial/8250/8250_bcm2835aux.ko.zst'])
    (w/'evidence/installed.ko').write_bytes(subprocess.check_output(['zstd','-dc'],input=z))
  def inspect(f):
    info={}
    for line in cmd('modinfo',str(f)).splitlines():
      k,_,v=line.partition(':');info.setdefault(k,[]).append(v.strip())
    vers={s[1]:s[0] for l in cmd('modprobe','--show-modversions',str(f)).splitlines() if len(s:=l.split())==2}
    sect=cmd('readelf','-SW',str(f));elf=cmd('readelf','-h',str(f));nm=cmd('nm',str(f))
    assert 'AArch64' in elf and '.BTF' in sect and '__version_ext_crcs' in sect
    assert not any('__ksymtab_' in l for l in nm.splitlines())
    assert info['intree']==['Y']
    sym={s[1]:s[0] for l in (w/'evidence/authenticated.symvers').read_text().splitlines() if len(s:=l.split())>=2}
    assert all(sym[k]==v for k,v in vers.items())
    return dict(sha256=digest(f),info=info,versions=vers,sections=sect,elf=elf,exports=[])
  a=inspect(w/'evidence/installed.ko');b=inspect(w/f'evidence/{label}.ko')
  for key in ('vermagic','name','license','alias','depends','author','description'):assert a['info'].get(key)==b['info'].get(key),(key,a['info'].get(key),b['info'].get(key))
  if label=='baseline':
    assert a['versions']==b['versions']
    assert a['info'].get('srcversion')==b['info'].get('srcversion')
  save(label+'-abi.json',dict(installed=a,rebuilt=b,added_imports=sorted(b['versions'].keys()-a['versions'].keys()),removed_imports=sorted(a['versions'].keys()-b['versions'].keys())))
  assert digest(w/'linux-7.3/.config')==digest(h/'.config')
  assert digest(w/'linux-7.3/Module.symvers')==digest(w/'evidence/authenticated.symvers')
