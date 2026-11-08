from pathlib import Path
import ast, difflib, hashlib, json, subprocess
r=Path(__file__).resolve().parents[2]; e=r/'companion-build'; before=e/'attempt-1/before'
for p in (r/'firmware').iterdir():
 if p.name != 'PKGBUILD': assert p.read_bytes()==(before/'firmware'/p.name).read_bytes(),p
print('PASS helper, hooks, baseline/config and DT source bytes unchanged')
for name in ['firmware/PKGBUILD','build-inside.sh','kernel/offline-inputs.sh']:
 subprocess.run(['bash','-n',str(r/name)],check=True)
ast.parse((r/'firmware-tests/alpm.py').read_text())
print('PASS shell syntax and Python parse')
for name in ['firmware/PKGBUILD','build-inside.sh','kernel/offline-inputs.sh','firmware-tests/alpm.py','INPUTS.sha256']:
 print(''.join(difflib.unified_diff((before/name).read_text().splitlines(True),(r/name).read_text().splitlines(True),fromfile='before/'+name,tofile=name)))
for path in [e/'attempt-1/container.json',e/'attempt-2/container.json',e/'attempt-2/verify-container.json',r/'firmware-tests/results/companion-split-1/container.json']:
 d=json.loads(path.read_text())[0]; h=d['HostConfig']; st=d['State']
 assert h['NanoCpus']==250000000 and h['Memory']==134217728 and h['MemorySwap']==134217728
 assert h['NetworkMode']=='none' and not h['Privileged'] and not h['Devices']
 assert not st['OOMKilled'] and not st['Running']
 assert st['ExitCode']==(1 if 'attempt-1' in str(path) else 0)
 print(path.relative_to(r), 'exit',st['ExitCode'],'OOM',st['OOMKilled'],'memory',h['Memory'],'swap-total',h['MemorySwap'],'cpu',h['NanoCpus'])
subprocess.run(['shasum','-a','256','-c','INPUTS.sha256'],cwd=r,check=True)
print('PASS complete INPUTS manifest')
