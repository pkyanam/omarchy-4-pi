import json,subprocess,struct,sys
from pathlib import Path
sys.path.insert(0,'/evidence')
from audit import digest,tree
ev=Path('/evidence'); repo=Path('/repo'); src=Path('/work/source'); k=Path('/work/headers/usr/lib/modules/7.3.0-32.1-omarchy/build')
def run(*a):return subprocess.check_output(a,text=True)
def read(p):return json.load(open(ev/p))
def save(n,x):json.dump(x,open(ev/n,'w'),indent=2)
a=read('headers-original-before.json'); b=read('headers-original-after.json'); c=read('headers-clone-before.json'); d=read('headers-clone-after.json')
assert a==b==c==d
save('headers-changes.json',{})
inputs=read('inputs-before.json'); after={n:digest(repo/n) for n in inputs}; assert inputs==after; save('inputs-after.json',after)
before=read('source-before.json'); current={n:tree(src)[n] for n in before}; assert before==current
assert read('artifacts.json')==tree(ev/'source')
def symvers(p):
  out={}
  for line in p.read_text().splitlines():
    v=line.split('\t');out[v[1]]={'crc':int(v[0],16),'provider':v[2],'export':v[3],'namespace':v[4] if len(v)>4 else ''}
  return out
base=symvers(k/'Module.symvers'); local=symvers(src/'Module.symvers'); symbols=base|local
save('export-collisions.json',{n:{'kernel':base[n],'external':local[n]} for n in base.keys()&local.keys()})
mods={}; detailed={}
with (ev/'symbols-elf.log').open('w') as log:
  for m in sorted(src.glob('*.ko')):
    raw=m.read_bytes(); assert raw[:6]==b'\x7fELF\x02\x01'; assert struct.unpack_from('<H',raw,18)[0]==183
    off=struct.unpack_from('<Q',raw,40)[0]; size,count,strings=struct.unpack_from('<HHH',raw,58)
    sh=[struct.unpack_from('<IIQQQQIIQQ',raw,off+i*size) for i in range(count)]
    st=sh[strings]; names=raw[st[4]:st[4]+st[5]]
    sections={names[s[0]:].split(b'\0',1)[0].decode():raw[s[4]:s[4]+s[5]] for s in sh if s[1]!=8}
    btf={}
    for n in ['.BTF','.BTF.base']:
      data=sections[n]; magic,version,flags,hlen,to,tl,so,sl=struct.unpack_from('<HBBIIIII',data)
      assert magic==0xeb9f and version==1 and tl>0 and sl>0 and hlen+so+sl<=len(data)
      btf[n]={'bytes':len(data),'version':version,'type_bytes':tl,'string_bytes':sl}
    debug=sections['.debug_info']; dwarf=struct.unpack_from('<H',debug,4)[0]; assert dwarf==5
    info=run('modinfo',str(m)); imports=set(run('modinfo','-F','import_ns',str(m)).splitlines()); vm=run('modinfo','-F','vermagic',str(m)).strip()
    assert vm=='7.3.0-32.1-omarchy SMP preempt mod_unload modversions aarch64'
    versions={v.split()[1]:int(v.split()[0],16) for v in run('modprobe','--show-modversions',str(m)).splitlines()}
    undefined={v.split()[-1] for v in run('nm','-u',str(m)).splitlines()}
    assert undefined<=versions.keys(),undefined-versions.keys()
    for n,crc in versions.items():
      assert n in symbols,(m,n)
      assert symbols[n]['crc']==crc,(m,n,crc,symbols[n])
      ns=symbols[n]['namespace']; assert not ns or ns in imports,(m,n,ns,imports)
    assert 'intree:' not in info
    assert '__versions' in sections and '__version_ext_crcs' in sections
    mods[m.name]={'sha256':digest(m),'bytes':len(raw),'machine':'AArch64','vermagic':vm,'dwarf_version':dwarf,'btf':btf,'imports':sorted(imports),'versioned_symbols_checked':len(versions),'undefined_symbols_checked':len(undefined),'external':True}
    detailed[m.name]={n:symbols[n] for n in versions}
    for cmd in [('modinfo',str(m)),('nm','-u',str(m)),('readelf','-h',str(m)),('readelf','-SW',str(m))]:
      log.write(str(cmd)+'\n'+run(*cmd)+'\n')
assert set(mods)=={'vchiq.ko','vc-sm-cma.ko','bcm2835-mmal-vchiq.ko','bcm2835-codec.ko'}
assert 'vchiq_add_connected_callback_sync' in detailed['vc-sm-cma.ko']
assert 'vchiq_remove_connected_callback' in detailed['vc-sm-cma.ko']
assert 'vchiq_register_connected_callback' not in detailed['vc-sm-cma.ko']
save('module-symbol-resolution.json',detailed)
save('modules.json',mods)
save('verification.json',{'whole_headers_original_clone_before_after_equal':True,'inputs_unchanged':True,'source_and_makefile_unchanged':True,'host_source_copy_matches_volume_artifacts':True,'protected':{n:digest(k/n) for n in ['.config','Module.symvers','vmlinux','include/config/kernel.release']},'compile_exit':int((ev/'compile.exit').read_text()),'modpost':'passed actual build','module_checks':'AArch64, expected vermagic, DWARF5, BTF and BTF.base headers and nonempty data, CRC resolution against actual kernel+combined Module.symvers, undefined symbol coverage and namespace imports','deployment_qualified':False})
print(json.dumps(mods,indent=2))
print(run('du','-sk','/work','/evidence'))
