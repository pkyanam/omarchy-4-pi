from pathlib import Path
import importlib.util, tempfile, subprocess, os, hashlib, difflib
c=Path('build/upstream-pi/stable-4.5/cts-kernel-candidate').resolve(); e=c/'kernel/preflight-evidence'; p=c/'kernel/check-config.py'
spec=importlib.util.spec_from_file_location('guard',p); guard=importlib.util.module_from_spec(spec); spec.loader.exec_module(guard)
a=c/'kernel/config.aarch64'; b=c/'kernel/reviewed-resolved.config'
guard.check(a,b)
with tempfile.TemporaryDirectory() as d:
 t=Path(d)/'config'
 for label, text in [('security', b.read_text().replace('CONFIG_RANDOMIZE_BASE=y','CONFIG_RANDOMIZE_BASE=n')),('architecture', b.read_text().replace('CONFIG_ARM64=y','CONFIG_ARM64=n')),('capability', b.read_text().replace('CONFIG_SERIAL_8250_BCM2835AUX=m','CONFIG_SERIAL_8250_BCM2835AUX=n')),('unknown-symbol',b.read_text()+'\nCONFIG_UNKNOWN_CTS_TEST=y\n'),('duplicate',b.read_text()+'\nCONFIG_ARM64=y\n'),('missing',b.read_text().replace('CONFIG_ARM64=y\n',''))]:
  assert text != b.read_text(),label
  t.write_text(text)
  try: guard.check(a,t)
  except ValueError as ex: print('PASS reject',label,str(ex)[:250])
  else: raise AssertionError(label)
 t.write_text('# harmless comment\n'+'\n'.join(reversed(b.read_text().splitlines()))+'\n'); guard.check(a,t)
 t.write_bytes(a.read_bytes()+b'\n')
 try: guard.check(t,b)
 except ValueError: print('PASS reject source hash drift')
 else: raise AssertionError('source drift')
# Actual source guard with available local tarball, not synthetic source behavior.
env=dict(os.environ,CTS_SOURCE_ONLY='1',PATH='/opt/homebrew/opt/coreutils/libexec/gnubin:'+os.environ['PATH'])
r=subprocess.run(['/bin/bash',str(c/'kernel/offline-inputs.sh'),str(c/'kernel'),str(c.parents[1])],env=env,text=True,capture_output=True,errors="replace")
print(r.stdout,r.stderr); assert r.returncode!=0
assert 'linux-7.3.tar.sign' in r.stderr and 'NVIDIA-kernel-module-source-615.78.08.tar.xz' in r.stderr
assert 'linux-7.3.tar.xz (' not in r.stderr
print('PASS missing real offline signature/NVIDIA inputs reject')
env=dict(os.environ); env.pop('CTS_BUILD_AUTHORIZED',None)
r=subprocess.run(['/bin/bash',str(c/'build-offline.sh')],env=env,text=True,capture_output=True,errors="replace")
assert r.returncode!=0 and 'parent build authorization required' in r.stderr
print('PASS runner rejects unauthorized invocation before Docker')
for path in [c/'build-inside.sh',c/'build-offline.sh',c/'verify-packages.sh',c/'kernel/offline-inputs.sh',c/'kernel/PKGBUILD']:
 subprocess.run(['/bin/bash','-n',str(path)],check=True);print('PASS syntax',path.name)
(e/'source-vs-resolved.diff').write_text(''.join(difflib.unified_diff(a.read_text().splitlines(True),b.read_text().splitlines(True),fromfile='reviewed-source',tofile='reviewed-resolved')))
for key in sorted((c/'kernel/keys/pgp').glob('*.asc')):
 with tempfile.TemporaryDirectory() as d:
  r=subprocess.run(['gpg','--homedir',d,'--batch','--show-keys','--with-colons',str(key)],text=True,capture_output=True,check=True)
  print('KEY FILE',key.name); print(r.stdout)
  assert f'fpr:::::::::{key.stem}:' in r.stdout
print('PASS bundled primary key fingerprints (not signature verification)')
