import subprocess,time,json,os
from pathlib import Path
p=Path(__file__).resolve().parent
name='h264-combined-12-build'
def run(*args):return subprocess.check_output(args,text=True).strip()
def allocated(root):
  return sum(f.stat().st_blocks*512 for f in root.rglob('*') if f.is_file())
start=time.monotonic()
with (p/'supervisor.jsonl').open('w',buffering=1) as log,(p/'run.log').open('w') as output:
  log.write(json.dumps({'event':'baseline','host_allocated':allocated(p),'df':run('df','-k',str(p)),'prior_conservative_charge_bytes':6473000000,'new_ceiling_bytes':1000000000,'stop_threshold_bytes':800000000})+'\n')
  process=subprocess.Popen(['docker','start','-a',name],stdout=output,stderr=subprocess.STDOUT)
  while process.poll() is None:
    time.sleep(5)
    info=json.loads(run('docker','inspect','--size',name))[0]
    if info['State']['Running']:
      measurement=subprocess.run(['docker','exec',name,'du','-sk','/work'],capture_output=True,text=True)
      if measurement.returncode: continue
      volume=int(measurement.stdout.split()[0])*1024
    else: volume=0
    host=allocated(p); rw=info.get('SizeRw',0)
    record={'elapsed_seconds':time.monotonic()-start,'host_allocated':host,'volume_allocated':volume,'root_rw':rw,'total':host+volume+rw,'running':info['State']['Running']}
    log.write(json.dumps(record)+'\n')
    if record['total']>=800000000 or record['elapsed_seconds']>=1500:
      log.write(json.dumps({'event':'safe-stop','reason':'storage or 25min active deadline'})+'\n')
      subprocess.run(['docker','stop','-t','5',name],stdout=output,stderr=output)
  process.wait()
  log.write(json.dumps({'event':'exit','status':process.returncode,'elapsed_seconds':time.monotonic()-start})+'\n')
(p/'container-inspect.json').write_text(run('docker','inspect','--size',name))
