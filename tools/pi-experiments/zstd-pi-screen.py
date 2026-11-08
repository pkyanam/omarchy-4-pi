#!/usr/bin/env python3
"""Parent-only, read-only 4GB Pi zstd screening; no system binary replacement.

Five balanced blocks of one real-source corpus at level3. This is a bounded
subset of the full matrix, with health and desktop-state rejection gates.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

HERE = Path.cwd()
BINS = ['bin/zstd-armv8-o2', 'bin/zstd-a72-tune-o2', 'bin/zstd-armv8-o3', '/usr/bin/zstd']
TEMP = Path('/sys/class/thermal/thermal_zone0/temp')
ALARMS = list(Path('/sys/class/hwmon').glob('*/in0_lcrit_alarm'))
EXPECTED = 'f1cb05ca79a264c240772c789429fc6ecd0d9e5fcd8be5fdeb98338841d65d2c'

def command(argv):
  return subprocess.check_output(argv, text=True, timeout=10).strip()

def desktop():
  monitors = json.loads(command(['hyprctl', 'monitors', '-j']))
  return {'locked': command(['omarchy-shell', 'lock', 'isLocked']),
          'outputs': [{k:m[k] for k in ('name','width','height','refreshRate','scale','dpmsStatus')} for m in monitors]}

def health():
  values = {'temp_millic': int(TEMP.read_text()),
            'voltage_alarm': [a.read_text().strip() for a in ALARMS],
            'requested_freq_khz': int(Path('/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq').read_text())}
  if values['temp_millic'] >= 75000 or any(x != '0' for x in values['voltage_alarm']):
    raise RuntimeError('health stop')
  return values

def main():
  assert ALARMS, 'native voltage alarm required'
  assert hashlib.sha256(Path('corpus/source.tar').read_bytes()).hexdigest() == EXPECTED
  initial = desktop()
  assert initial['locked'] == 'true', 'this run requires the recorded locked desktop'
  assert len(initial['outputs']) == 1 and initial['outputs'][0]['scale'] == 2
  assert command(['cat','/sys/devices/system/cpu/cpufreq/policy0/scaling_governor']) == 'schedutil'
  out = HERE / ('pi-screen-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
  out.mkdir()
  report = {'protocol':'zstd-source-level3-screen-v1', 'status':'running',
            'board_cohort':'pi4-4gb-native', 'kernel':os.uname().release,
            'initial_desktop':initial, 'corpus_sha256':EXPECTED,
            'affinity_cpu':2, 'iteration_seconds':1, 'level':3, 'blocks':5,
            'packages':command(['pacman','-Q','zstd','glibc','omarchy','linux-omarchy']),
            'binaries':{b:hashlib.sha256(Path(b).read_bytes()).hexdigest() for b in BINS},
            'firmware_actual_clock':None, 'firmware_throttle':None, 'energy':None,
            'trials':[]}
  deadline = time.monotonic() + 600
  try:
    for block in range(-1,5):
      order = range(4) if block % 2 == 0 else range(3,-1,-1)
      for idx in order:
        while health()['temp_millic'] > 52000:
          if time.monotonic() > deadline:
            raise RuntimeError('bounded cooling budget exhausted')
          time.sleep(2)
        if desktop() != initial:
          raise RuntimeError('desktop changed; reject complete comparison')
        before = health()
        pressure_before = {x:Path('/proc/pressure/'+x).read_text() for x in ('cpu','memory','io')}
        args = ['taskset','-c','2',BINS[idx],'--single-thread','-b3','-i1','corpus/source.tar']
        start_cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
        start = time.monotonic()
        samples = []
        rawpath = out / f'block{block}-variant{idx}.log'
        with rawpath.open('wb') as raw:
          process = subprocess.Popen(args, stdout=raw, stderr=subprocess.STDOUT)
          try:
            while process.poll() is None:
              samples.append(health())
              if time.monotonic()-start > 30:
                raise RuntimeError('trial exceeded30seconds')
              time.sleep(.2)
          finally:
            if process.poll() is None:
              process.terminate()
              process.wait(timeout=5)
        end_cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
        trial = {'block':block,'warmup':block==-1,'variant':idx,'argv':args,
                 'wall_s':time.monotonic()-start,
                 'cpu_s':end_cpu.ru_utime+end_cpu.ru_stime-start_cpu.ru_utime-start_cpu.ru_stime,
                 'before':before,'samples':samples,'after':health(),
                 'pressure_before':pressure_before,
                 'pressure_after':{x:Path('/proc/pressure/'+x).read_text() for x in ('cpu','memory','io')},
                 'exit_code':process.returncode,'raw_log':rawpath.name}
        report['trials'].append(trial)
        (out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        if process.returncode != 0:
          raise RuntimeError('zstd trial failed')
        print(f'block{block} variant{idx} complete', flush=True)
    assert desktop() == initial, 'desktop changed during final trial'
    report['status'] = 'complete'
  except BaseException as exc:
    report['status'] = 'rejected'
    report['reason'] = str(exc)
    raise
  finally:
    (out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(out,flush=True)

if __name__ == '__main__':
  main()
