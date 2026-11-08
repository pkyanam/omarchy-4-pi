import subprocess,pathlib,time,json,sys
p=pathlib.Path(__file__).resolve().parent
n=sys.argv[1]; threshold=int(sys.argv[2]) if len(sys.argv)>2 else 1200000000
base=None;peak=0;start=time.monotonic()
def out(*a):return subprocess.check_output(a,text=True,stderr=subprocess.PIPE)
def stop(reason):
 (p/'logs'/f'{n}-stop.txt').write_text(reason)
 subprocess.run(['docker','stop','-t','5',n],check=True)
try:
 with (p/'logs'/f'{n}-storage.jsonl').open('w') as log:
  while json.loads(out('docker','inspect',n))[0]['State']['Running']:
   host=int(out('du','-sk',str(p)).split()[0])*1024
   if len(sys.argv)>3 and base is not None:raise RuntimeError('injected accounting unavailability')
   root,vol=[int(l.split()[0]) for l in out('docker','exec',n,'du','-sx','-B1','/','/work').splitlines()]
   if base is None:base=root
   charge=host+vol+max(0,root-base)+16000000;peak=max(peak,charge)
   log.write(json.dumps(dict(time=time.time(),host=host,root=root,volume=vol,charged=charge,peak=peak))+'\n');log.flush()
   if charge>=threshold:stop('allocated stop threshold');break
   if time.monotonic()-start>1800:stop('30 minute execution deadline');break
   time.sleep(2)
except Exception as e:
 (p/'logs'/f'{n}-accounting-error.txt').write_text(repr(e))
 if out('docker','inspect','-f','{{.State.Running}}',n).strip()=='true':stop('accounting failure')
finally:
 (p/'logs'/f'{n}-inspect.json').write_text(out('docker','inspect',n))
