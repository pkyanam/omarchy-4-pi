import ast, hashlib, json, os, re, subprocess
from pathlib import Path
root=Path('/work'); report={}
def call(cmd,env,data=None,fail=False):
 r=subprocess.run(list(map(str,cmd)),input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
 if fail: assert r.returncode!=0,cmd
 elif r.returncode: raise RuntimeError(f'{cmd}: {r.stderr.decode(errors="replace")}')
 return r.stdout
data=(root/'O2/src/zstd-1.5.7/tests/fuzzer.c').read_bytes()
for opt in (2,3):
 d=root/f'O{opt}';a=d/'audit';lib=a/'extracted/usr/lib';cli=a/'extracted/usr/bin/zstd'
 env=dict(os.environ,LD_LIBRARY_PATH=str(lib))
 logs=[]
 def z(args,data=None,fail=False): return call([cli,*args],env,data,fail)
 for fmt in ('zstd','gzip','xz','lzma','lz4'):
  encoded=z(['-q','--format='+fmt,'-c'],data)
  assert z(['-q','-dc'],encoded)==data
  (a/f'format-{fmt}.bin').write_bytes(encoded);logs.append('roundtrip '+fmt)
 encoded=z(['-q','-T2','-c'],data)
 assert z(['-q','-dc'],encoded)==data
 (a/'threaded.zst').write_bytes(encoded);logs.append('thread T2 roundtrip')
 for wrapper in ('unzstd','zstdcat'):
  assert call([a/'extracted/usr/bin'/wrapper,'-q','-c'],env,encoded)==data
 assert call([a/'extracted/usr/bin/zstdmt','-q','-dc'],env,encoded)==data
 pz=a/'extracted/usr/bin/pzstd'
 packed=call([pz,'-q','-p','1','-c'],env,data)
 assert call([pz,'-q','-p','1','-dc'],env,packed)==data
 logs.append('unzstd/zstdcat/zstdmt wrappers and pzstd roundtrip')
 sources=list((d/'src/zstd-1.5.7/tests').glob('*.c'))
 dictionary=a/'dictionary'
 z(['--train','-q',*sources,'-o',dictionary,'--maxdict=8192'])
 encoded=z(['-q','-D',dictionary,'-c'],data)
 assert z(['-q','-D',dictionary,'-dc'],encoded)==data
 logs.append('trained dictionary roundtrip')
 z(['-q','-dc'],b'not a zstd frame',True)
 z(['-q','-dc'],encoded[:-7],True)
 for fixture in (d/'src/zstd-1.5.7/tests/golden-decompression-errors').iterdir():
  if fixture.is_file(): z(['-q','-t',fixture],fail=True)
 logs.append('malformed/truncated/golden-error rejection')
 # Decode upstream's unchanged embedded legacy frames, using expected source bytes.
 source=(d/'src/zstd-1.5.7/tests/legacy.c').read_text()
 def strings(name):
  body=re.search(r'const char\* const '+name+r'\s*=\s*(.*?);',source,re.S).group(1)
  parts=re.findall(r'"(?:[^"\\]|\\.)*"',body)
  if name=='COMPRESSED': return b''.join(ast.literal_eval('b'+p) for p in parts)
  return ''.join(ast.literal_eval(p) for p in parts).encode()
 legacy=strings('COMPRESSED'); expected=strings('EXPECTED')
 assert len(legacy)==917
 # Upstream fixture concatenates v0.4, v0.5, v0.6, v0.7 and current frames.
 # This package's unchanged LEGACY_LEVEL=5 intentionally excludes v0.4.
 starts=[i for i in range(len(legacy)-3) if legacy[i+1:i+4]==bytes.fromhex('b52ffd')]
 assert [legacy[i] for i in starts]==[0x24,0x25,0x26,0x27,0x28]
 assert len(expected)%5==0
 one=expected[:len(expected)//5];assert one*5==expected
 for index,start in enumerate(starts):
  frame=legacy[start:starts[index+1] if index+1<len(starts) else len(legacy)]
  if index==0: z(['-q','-dc'],frame,True)
  else: assert z(['-q','-dc'],frame)==one
 assert z(['-q','-dc'],legacy[starts[1]:])==one*4
 (a/'legacy-fixture.zst').write_bytes(legacy);(a/'legacy-expected.txt').write_bytes(expected)
 logs.append('upstream v0.5/v0.6/v0.7/current fixtures and concatenation decoded exactly; excluded v0.4 rejected')
 other=3 if opt==2 else 2
 otherroot=root/f'O{other}/audit/extracted'
 otherenv=dict(os.environ,LD_LIBRARY_PATH=str(otherroot/'usr/lib'))
 for fmt in ('zstd','gzip','xz','lzma','lz4'):
  assert call([otherroot/'usr/bin/zstd','-q','-dc'],otherenv,(a/f'format-{fmt}.bin').read_bytes())==data
 logs.append('all formats cross-decoded with other candidate own shared library')
 stock=root/'reference-extracted'
 stockenv=dict(os.environ,LD_LIBRARY_PATH=str(stock/'usr/lib'))
 trace=call(['/lib/ld-linux-aarch64.so.1','--list',stock/'usr/bin/zstd'],stockenv).decode()
 assert str(stock/'usr/lib/libzstd.so.1') in trace
 for fmt in ('zstd','gzip','xz','lzma','lz4'):
  assert call([stock/'usr/bin/zstd','-q','-dc'],stockenv,(a/f'format-{fmt}.bin').read_bytes())==data
  stockframe=call([stock/'usr/bin/zstd','-q','--format='+fmt,'-c'],stockenv,data)
  assert z(['-q','-dc'],stockframe)==data
 logs.append('all formats bidirectionally cross-decoded with authenticated stock own shared library')
 (a/'smoke.json').write_text(json.dumps(logs,indent=2));report[f'O{opt}']=logs
(root/'smoke-summary.json').write_text(json.dumps(report,indent=2)); print(json.dumps(report,indent=2))
