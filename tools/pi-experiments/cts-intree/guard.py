import subprocess,pathlib,time,json,sys
p=pathlib.Path(__file__).resolve().parent;n='cts-intree-candidate-1';base=None;peak=0
start=time.monotonic()
log=(p/'logs/storage.jsonl').open('a')
def out(*a):return subprocess.check_output(a,text=True,stderr=subprocess.PIPE)
def stop(reason):
  (p/'logs/stop-reason.txt').write_text(reason+'\n');subprocess.run(['docker','stop','-t','5',n],check=True)
try:
  while True:
    state=json.loads(out('docker','inspect',n))[0]
    if not state['State']['Running']:break
    host=int(out('du','-sk',str(p)).split()[0])*1024
    sizes=out('docker','exec',n,'du','-sx','-B1','/','/work').splitlines()
    root,volume=[int(l.split()[0]) for l in sizes]
    if base is None:base=root
    # Read-only container root: conservatively charge its entire positive growth,
    # plus 16MB fixed reserve for injection/layer metadata. Archives bind read-only.
    charged=host+volume+max(0,root-base)+16000000
    peak=max(peak,charged)
    log.write(json.dumps(dict(time=time.time(),host=host,volume=volume,root=root,root_base=base,charged=charged,peak=peak))+'\n');log.flush()
    if charged>=3500000000:stop('3.5GB stop threshold');break
    if time.monotonic()-start>1800:stop('30 minute bounded execution deadline');break
    time.sleep(2)
except Exception as e:
  (p/'logs/measurement-error.txt').write_text(repr(e))
  if out('docker','inspect','-f','{{.State.Running}}',n).strip()=='true':stop('measurement unavailable; fail closed')
finally:
  (p/'logs/container-final.json').write_text(out('docker','inspect',n))
