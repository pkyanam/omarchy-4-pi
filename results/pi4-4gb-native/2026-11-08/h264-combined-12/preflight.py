import sys,json,subprocess,tarfile,shutil
from pathlib import Path
sys.path.insert(0,'/evidence')
from audit import digest,tree
repo=Path('/repo'); work=Path('/work'); ev=Path('/evidence')
old=repo/'build/upstream-pi/stable-4.5/h264-port-candidate'
snap=repo/'tools/pi-experiments/h264-port'
archive=repo/'build/upstream-pi/linux-7.3.tar.xz'
headers=repo/'build/upstream-pi/stable-4.5/kernel-reviewed/packages/linux-omarchy-headers-7.3-32.1-aarch64.pkg.tar.zst'
assert digest(archive)=='87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953'
assert digest(headers)=='1c90e860325eed52865869c060f762718784f9bda9cc9d7978fa636ce74f89e1'
inputs={str(p.relative_to(repo)):digest(p) for p in [archive,headers,snap/'replay-source.py',snap/'external-lifecycle-module.Makefile',snap/'patches/series']}
names=(snap/'patches/series').read_text().splitlines(); assert len(names)==12
for n in names:
  p=snap/'patches'/n
  if n in names[:11]: assert p.read_bytes()==(old/'patches'/n).read_bytes()
  inputs[str(p.relative_to(repo))]=digest(p)
json.dump(inputs,open(ev/'inputs-before.json','w'),indent=2)
# Whole header clone, preserving authenticated configuration, symvers, and vmlinux.
original=tree(Path('/input/headers'))
json.dump(original,open(ev/'headers-original-before.json','w'),indent=2)
if not (work/'headers').exists():
  shutil.copytree('/input/headers',work/'headers',symlinks=True,copy_function=shutil.copy2)
clone=tree(work/'headers'); assert clone==original
json.dump(clone,open(ev/'headers-clone-before.json','w'),indent=2)
# Check all regular archive members byte-for-byte, on Linux, including case collisions.
proc=subprocess.Popen(['zstd','-dc',str(headers)],stdout=subprocess.PIPE)
count=0
with tarfile.open(fileobj=proc.stdout,mode='r|') as tf:
  for m in tf:
    rel=m.name.removeprefix('./')
    if not m.isfile(): continue
    import hashlib
    expected=hashlib.sha256(tf.extractfile(m).read()).hexdigest()
    assert digest(work/'headers'/rel)==expected,rel
    count+=1
assert proc.wait()==0
assert count==22575,count
print('Header archive regular members authenticated:',count,flush=True)
# Run the tracked streamed replay with an observed patch boundary; source/helper remain read-only.
import runpy,sys
real_run=subprocess.run
applied=[]
def checked_run(args,**kw):
  result=real_run(args,**kw)
  if args[0]=='patch':
    applied.append(names[len(applied)])
    a={k:v for k,v in tree(work/'source').items() if k.endswith(('.c','.h'))}
    if len(applied)==11:
      b={k:v for k,v in tree(repo/'build/upstream-pi/stable-4.5/h264-combined-11/source').items() if k.endswith(('.c','.h'))}
      assert a==b,'eleven-patch prefix differs from actual failed compiled source'
      json.dump(a,open(ev/'source-prefix-11.json','w'),indent=2)
    if len(applied)==12:
      before=json.load(open(ev/'source-prefix-11.json'))
      changed=[k for k in a if a[k]!=before.get(k)]
      assert changed==['drivers/platform/raspberrypi/vc-sm-cma/vc_sm.c'],changed
      f=changed[0]
      prior=(repo/'build/upstream-pi/stable-4.5/h264-combined-11/source'/f).read_bytes()
      assert (work/'source'/f).read_bytes()==prior.replace(b'vchiq_register_connected_callback(device, vc_sm_connected_init)',b'vchiq_add_connected_callback_sync(device, vc_sm_connected_init)')
      json.dump({'changed':changed,'exact_single_call_replacement':True},open(ev/'patch12-delta.json','w'),indent=2)
  return result
subprocess.run=checked_run
sys.argv=[str(snap/'replay-source.py'),'--archive',str(archive),'--output',str(work/'source')]
runpy.run_path(str(snap/'replay-source.py'),run_name='__main__')
subprocess.run=real_run
assert applied==names
assert (work/'source/Makefile').read_bytes()==(repo/'build/upstream-pi/stable-4.5/h264-combined-11/source/Makefile').read_bytes()
a={k:v for k,v in tree(work/'source').items() if k.endswith(('.c','.h')) or k=='Makefile'}
assert len(a)==31
json.dump(a,open(ev/'source-before.json','w'),indent=2)
json.dump({n:digest(snap/'patches'/n) for n in names},open(ev/'series.json','w'),indent=2)
print('Fresh tracked 12-patch replay: exact failed 11-prefix; only patch12 single-call delta; 30 C/headers + Makefile',flush=True)
