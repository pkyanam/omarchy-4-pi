import hashlib,json,os,signal,subprocess,time
from pathlib import Path
out=Path('/root/omarchy-pi-optimization-20261108/bt-cts-window-1')
out.mkdir(mode=0o700)
fdt=Path('/sys/firmware/fdt').read_bytes();(out/'current.fdt').write_bytes(fdt)
(out/'fdt.sha256').write_text(hashlib.sha256(fdt).hexdigest()+'\n')
base=Path('/home/preetham/.cache/omarchy-optimization/bluetooth-scalar')
obs_cmd=['timeout','--signal=TERM','--kill-after=1s','45s','python3',str(base/'bluetooth-cts-snapshot.py'),'--observe-actions',str(out/'uart/actions.json'),'--output',str(out/'gpio.jsonl')]
trace_cmd=['python3',str(base/'bluetooth-uart-progress.py'),'--execute','--identity',str(base/'parent-identity.json'),'--expected-formats','6d62cbec3af7b5245fb9cbf6ebce8a17bece4691dda5ea3e3a61efbd661d054b','--output',str(out/'uart')]
result={'observer_command':obs_cmd,'trace_command':trace_cmd,'trace_started':False}
observer=trace=None
with (out/'observer.log').open('w') as ol,(out/'trace.log').open('w') as tl:
  try:
    observer=subprocess.Popen(obs_cmd,stdout=ol,stderr=subprocess.STDOUT,start_new_session=True)
    result['observer_pid']=observer.pid
    until=time.monotonic()+3
    while True:
      if observer.poll() is not None:raise RuntimeError('observer exited before arming')
      try:
        with (out/'gpio.jsonl').open() as f:armed=json.loads(f.readline(4096))
        if 'armed' in armed and armed['pid']>0:break
      except (FileNotFoundError,json.JSONDecodeError):pass
      if time.monotonic()>until:raise RuntimeError('observer arm deadline')
      time.sleep(.02)
    result['armed']=armed
    trace=subprocess.Popen(trace_cmd,stdout=tl,stderr=subprocess.STDOUT,start_new_session=True)
    result.update(trace_started=True,trace_pid=trace.pid)
    try:result['trace_exit']=trace.wait(timeout=30)
    except subprocess.TimeoutExpired:
      trace.terminate()
      try:result['trace_exit']=trace.wait(timeout=8)
      except subprocess.TimeoutExpired:result['unresolved_trace_pid']=trace.pid
      raise RuntimeError('trace exceeded controller deadline; review owned cleanup')
    try:result['observer_exit']=observer.wait(timeout=5)
    except subprocess.TimeoutExpired:raise RuntimeError('observer did not settle after trace')
  except BaseException as error:
    result['error']=str(error)
  finally:
    if observer and observer.poll() is None:
      os.killpg(observer.pid,signal.SIGTERM)
      try:result['observer_exit']=observer.wait(timeout=2)
      except subprocess.TimeoutExpired:result['unresolved_observer_pid']=observer.pid
    result['finished_monotonic']=time.monotonic()
    (out/'controller-result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
raise SystemExit(0 if result.get('trace_exit')==0 and result.get('observer_exit')==0 and 'error' not in result else 1)
