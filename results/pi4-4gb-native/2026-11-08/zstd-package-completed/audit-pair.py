import ast, hashlib, json, os, re, shlex, subprocess, tarfile
from pathlib import Path
root=Path('/work')
def run(cmd, env=None, data=None):
 r=subprocess.run(list(map(str,cmd)),input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
 if r.returncode: raise RuntimeError(f'{cmd}: {r.returncode}: {r.stderr.decode(errors="replace")}')
 return r.stdout
def sha(p): return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
def norm(s):
 return s.replace('/O2/','/OPT/').replace('/O3/','/OPT/').replace('-O2','-OPT').replace('-O3','-OPT')
summary={}
reference=root/'reference-extracted';reference.mkdir(exist_ok=True)
run(['tar','-xf',root/'zstd-1.5.7-3-aarch64.pkg.tar.xz','-C',reference])
for opt in (2,3):
 d=root/f'O{opt}'; a=d/'audit'; a.mkdir(exist_ok=True)
 pkgs=list(d.glob('*.pkg.tar.*')); assert len(pkgs)==1,pkgs
 pkg=pkgs[0]; extract=a/'extracted';extract.mkdir(exist_ok=True)
 run(['tar','-xf',pkg,'-C',extract])
 for meta in ('.BUILDINFO','.PKGINFO','.MTREE'):
  (a/meta.lstrip('.')).write_bytes((extract/meta).read_bytes())
 (a/'package-files.txt').write_bytes(run(['tar','-tvf',pkg]))
 build=d/'src/zstd-1.5.7/build'
 db=json.loads((build/'compile_commands.json').read_text())
 actual=(d/'compiler-argv.log').read_text().splitlines()
 required=['-march=armv8-a','-fstack-protector-strong','-fstack-clash-protection','-fno-omit-frame-pointer','-Werror=format-security','-fexceptions']
 for command in [x['command'] for x in db]+actual:
  tokens=shlex.split(command)
  assert [x for x in tokens if x.startswith('-O')]==[f'-O{opt}']
  assert all(x in tokens for x in required)
  assert any('D_FORTIFY_SOURCE=3' in x for x in tokens)
  assert not any(x.startswith(('-mcpu=','-mtune=','-flto','-fprofile','-ffast-math')) for x in tokens)
 assert len(actual)==len(db)
 (a/'normalized-compilers.json').write_text(json.dumps(sorted(norm(x) for x in actual),indent=2))
 links=[re.sub(r'^\[\d+/\d+\] ','',s) for s in (d/'build.log').read_text().splitlines() if re.match(r'^\[\d+/\d+\] ',s) and any(' '+cc+' ' in ' '+s for cc in ('/usr/bin/cc','/usr/bin/c++')) and ' -o ' in s and ' -c ' not in s]
 assert links
 assert all('-Wl,-z,relro' in s and '-Wl,-z,now' in s for s in links)
 (a/'actual-links.txt').write_text('\n'.join(links))
 (a/'normalized-links.json').write_text(json.dumps(sorted(norm(x) for x in links),indent=2))
 cache=(build/'CMakeCache.txt').read_text()
 (a/'normalized-cache.txt').write_text(norm(cache))
 for feature in ['ZSTD_BUILD_SHARED','ZSTD_MULTITHREAD_SUPPORT','ZSTD_LEGACY_SUPPORT','ZSTD_ZLIB_SUPPORT','ZSTD_LZMA_SUPPORT','ZSTD_LZ4_SUPPORT','ZSTD_BUILD_CONTRIB','ZSTD_BUILD_TESTS','ZSTD_PROGRAMS_LINK_SHARED','ZSTD_BUILD_DICTBUILDER']:
  assert re.search(r'^'+feature+r':\w+=ON$',cache,re.M),feature
 assert re.search(r'^ZSTD_LEGACY_LEVEL:\w+=5$',cache,re.M)
 assert re.search(r'^ZSTD_BUILD_STATIC:\w+=OFF$',cache,re.M)
 cli=extract/'usr/bin/zstd';lib=extract/'usr/lib/libzstd.so.1.5.7'
 for name,elf in [('cli',cli),('library',lib),('reference-library',root/'stock-libzstd.so.1.5.7'),('reference-cli',root/'stock-zstd')]:
  elfdata=run(['readelf','-h','-l','-d','-n','-W','--version-info',elf]).decode()
  (a/f'{name}.elf').write_text(elfdata)
  assert 'GNU_RELRO' in elfdata and 'BIND_NOW' in elfdata
  stack=next(x for x in elfdata.splitlines() if 'GNU_STACK' in x); assert ' RWE ' not in stack
  if name=='cli': assert 'DYN (Position-Independent Executable file)' in elfdata
  symbols=run(['readelf','--dyn-syms','--wide',elf]).decode()
  (a/f'{name}.symbols').write_text(symbols)
  exports=sorted(set(line.split()[7] for line in symbols.splitlines() if len(line.split())>=8 and line.split()[4] in ('GLOBAL','WEAK') and line.split()[6]!='UND'))
  (a/f'{name}.exports').write_text('\n'.join(exports))
 assert (a/'library.exports').read_bytes()==(a/'reference-library.exports').read_bytes()
 assert '(SONAME)' in (a/'library.elf').read_text() and '[libzstd.so.1]' in (a/'library.elf').read_text()
 for name in ('library','cli'):
  versions=set(re.findall(r'Name: (GLIBC_[^ ]+)',(a/f'{name}.elf').read_text()))
  ref=set(re.findall(r'Name: (GLIBC_[^ ]+)',(a/f'reference-{name}.elf').read_text()))
  # Packed relative relocations add this ABI marker to the candidate library.
  # Parent reports target glibc2.43; DT_RELR is supported since glibc2.36.
  # This is a target-version compatibility inference, not execution on the Pi.
  target_glibc=(2,43)
  allowed={'GLIBC_ABI_DT_RELR'} if target_glibc >= (2,36) else set()
  assert versions<=ref|allowed,(versions,ref)
  (a/f'{name}.additional-version-requirements.json').write_text(json.dumps(sorted(versions-ref)))
 env=dict(os.environ,LD_LIBRARY_PATH=str(extract/'usr/lib'))
 loader=run(['/lib/ld-linux-aarch64.so.1','--list',cli],env).decode();(a/'loader.txt').write_text(loader)
 assert str(extract/'usr/lib/libzstd.so.1') in loader
 (a/'version.txt').write_bytes(run([cli,'-vvV'],env))
 for elf in (extract/'usr').rglob('*'):
  if elf.is_symlink() or not elf.is_file() or elf.open('rb').read(4)!=b'\x7fELF': continue
  rel=elf.relative_to(extract);ref=reference/rel
  ed=run(['readelf','-h','-l','-d','-W','--version-info',elf]).decode()
  (a/(elf.name+'.package-elf')).write_text(ed)
  assert 'GNU_RELRO' in ed and 'BIND_NOW' in ed
  assert ' RWE ' not in next(x for x in ed.splitlines() if 'GNU_STACK' in x)
  if str(rel).startswith('usr/bin/'):
    assert 'DYN (Position-Independent Executable file)' in ed
    trace=run(['/lib/ld-linux-aarch64.so.1','--list',elf],env).decode()
    (a/(elf.name+'.loader')).write_text(trace)
    assert str(extract/'usr/lib/libzstd.so.1') in trace
  assert ref.exists(),str(rel)
  rd=run(['readelf','--version-info',ref]).decode()
  needed=set(re.findall(r'Name: ((?:GLIBC|GLIBCXX|CXXABI)_[^ ]+)',ed))
  provided=set(re.findall(r'Name: ((?:GLIBC|GLIBCXX|CXXABI)_[^ ]+)',rd))
  assert needed<=provided|allowed,(str(rel),needed-provided)
 summary[f'O{opt}']={'package':str(pkg),'sha256':sha(pkg),'cli_sha256':sha(cli),'library_sha256':sha(lib),'compile_database_count':len(db),'actual_compiler_count':len(actual),'actual_link_count':len(links)}
for name in ('normalized-compilers.json','normalized-links.json','normalized-cache.txt'):
 assert (root/'O2/audit'/name).read_bytes()==(root/'O3/audit'/name).read_bytes(),name
# Compare the runtime contract against authenticated stock metadata.
def metadata(path):
 result={}
 for line in path.read_text().splitlines():
  if ' = ' in line:
   key,value=line.split(' = ',1);result.setdefault(key,[]).append(value)
 return result
stock=metadata(reference/'.PKGINFO')
for opt in (2,3):
 candidate=metadata(root/f'O{opt}/audit/extracted/.PKGINFO')
 for key in ('pkgname','pkgbase','arch','provides','depend','license'):
  assert candidate.get(key)==stock.get(key),(opt,key)
 assert candidate['pkgver']==['1.5.7-3.1']
 assert candidate['builddate']==['1771243807']
# Package path/type/mode/link layouts must match.
def layout(d):
 return sorted((str(p.relative_to(d)),p.lstat().st_mode,os.readlink(p) if p.is_symlink() else None) for p in d.rglob('*'))
assert layout(root/'O2/audit/extracted')==layout(root/'O3/audit/extracted')
stocklayout=layout(reference/'usr')
for opt in (2,3):
 candidatelayout=layout(root/f'O{opt}/audit/extracted/usr')
 differences={'missing_or_changed':sorted(set(stocklayout)-set(candidatelayout)), 'extra_or_changed':sorted(set(candidatelayout)-set(stocklayout))}
 (root/f'O{opt}/audit/layout-vs-stock.json').write_text(json.dumps(differences,indent=2))
 assert candidatelayout==stocklayout,differences
(root/'audit-summary.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
