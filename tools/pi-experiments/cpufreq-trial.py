#!/usr/bin/env python3
"""Bounded reversible CPUFreq experiment; run as root on the designated Pi.

Writes JSON only; changes one governor, always restoring it. Firmware actual
clock/throttle and energy remain unknown. This is compute, not desktop speed.
"""
import hashlib
import json
import multiprocessing as mp
import os
from pathlib import Path
import signal
import time

POLICY = Path('/sys/devices/system/cpu/cpufreq/policy0')
TEMP = Path('/sys/class/thermal/thermal_zone0/temp')

def read(path):
  return Path(path).read_text().strip()

def worker(end, queue):
  data = bytes(range(256)) * 4096
  count = 0
  start_cpu = time.process_time()
  while time.monotonic() < end:
    hashlib.sha256(data).digest()
    count += 1
  queue.put((count, time.process_time() - start_cpu))

def interrupted(signum, frame):
  raise InterruptedError(f'signal {signum}')

def main():
  if os.geteuid() != 0:
    raise SystemExit('root required for reversible governor selection')
  original = read(POLICY / 'scaling_governor')
  if original != 'schedutil':
    raise SystemExit('requires recorded schedutil baseline')
  alarms = list(Path('/sys/class/hwmon').glob('*/in0_lcrit_alarm'))
  if not alarms:
    raise SystemExit('native voltage alarm unavailable')
  for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(sig, interrupted)
  results = []
  children = []
  try:
    for governor in ('schedutil', 'performance', 'performance', 'schedutil'):
      # Cooldown is bounded and checks health; it is not a desktop daemon.
      deadline = time.monotonic() + 120
      while int(read(TEMP)) > 48000:
        if time.monotonic() > deadline:
          raise RuntimeError('cooldown exceeded 120 seconds')
        time.sleep(2)
      if any(read(a) != '0' for a in alarms):
        raise RuntimeError('voltage alarm before trial')
      (POLICY / 'scaling_governor').write_text(governor)
      time.sleep(2)
      queue = mp.Queue()
      start = time.monotonic()
      end = start + 20
      children = [mp.Process(target=worker, args=(end, queue)) for _ in range(4)]
      samples = []
      for child in children:
        child.start()
      while any(child.is_alive() for child in children):
        temp = int(read(TEMP))
        voltage = [read(a) for a in alarms]
        samples.append({'elapsed_s': time.monotonic() - start, 'temp_millic': temp,
                        'requested_freq_khz': int(read(POLICY / 'scaling_cur_freq')),
                        'voltage_alarm': voltage})
        if temp >= 75000 or any(v != '0' for v in voltage):
          raise RuntimeError('health stop')
        time.sleep(1)
      outputs = [queue.get(timeout=2) for _ in children]
      for child in children:
        child.join()
        if child.exitcode != 0:
          raise RuntimeError('worker failed')
      results.append({'governor': governor, 'duration_target_s': 20, 'workers': 4,
                      'mib_hashed': sum(x[0] for x in outputs),
                      'worker_cpu_s': sum(x[1] for x in outputs), 'samples': samples,
                      'pressure_after': read('/proc/pressure/cpu')})
      (POLICY / 'scaling_governor').write_text(original)
      time.sleep(10)
  finally:
    for child in children:
      if child.is_alive():
        child.terminate()
      child.join()
    (POLICY / 'scaling_governor').write_text(original)
    print(json.dumps({'workload': 'python-hashlib-sha256-1mib-v1', 'kernel': os.uname().release,
                      'openssl': __import__('ssl').OPENSSL_VERSION,
                      'original_governor': original, 'restored_governor': read(POLICY / 'scaling_governor'),
                      'firmware_actual_clock': None, 'firmware_throttled': None, 'energy': None,
                      'trials': results}, indent=2), flush=True)

if __name__ == '__main__':
  main()
