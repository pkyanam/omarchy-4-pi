#!/usr/bin/env python3
"""Compare named kernel software XTS transforms; public test key, no disk I/O."""
import json
from pathlib import Path
import socket
import struct
import time

KEY = bytes(range(64))  # Public fixture only; never used for storage.
DATA = bytes(range(256)) * 256
IV = struct.pack('I', 16) + bytes(16)
TEMP = Path('/sys/class/thermal/thermal_zone0/temp')
ALARMS = list(Path('/sys/class/hwmon').glob('*/in0_lcrit_alarm'))

def connection(name):
  parent = socket.socket(socket.AF_ALG, socket.SOCK_SEQPACKET)
  parent.bind(('skcipher', name))
  parent.setsockopt(socket.SOL_ALG, socket.ALG_SET_KEY, KEY)
  operation, _ = parent.accept()
  return parent, operation

def encrypt(operation):
  sent = operation.sendmsg([DATA], [(socket.SOL_ALG, socket.ALG_SET_OP,
                                   struct.pack('I', socket.ALG_OP_ENCRYPT)),
                                  (socket.SOL_ALG, socket.ALG_SET_IV, IV)])
  if sent != len(DATA):
    raise RuntimeError('partial send')
  output = operation.recv(len(DATA))
  if len(output) != len(DATA):
    raise RuntimeError('partial receive')
  return output

def main():
  if not ALARMS:
    raise RuntimeError('native voltage alarm required')
  import argparse
  parser = argparse.ArgumentParser()
  parser.add_argument('--phase', required=True)
  args = parser.parse_args()
  names = ('xts(aes)',)
  results = []
  expected = None
  for pair in range(3):
    for name in (names if pair % 2 == 0 else names[::-1]):
      parent, op = connection(name)
      try:
        output = encrypt(op)
        if expected is None:
          expected = output
        if output != expected:
          raise RuntimeError('ciphertext mismatch')
        start = time.monotonic()
        cpu = time.process_time()
        count = 0
        samples = []
        last = start - 1
        while time.monotonic() - start < 3:
          encrypt(op)
          count += 1
          now = time.monotonic()
          if now - last > .2:
            temp = int(TEMP.read_text())
            alarm = [a.read_text().strip() for a in ALARMS]
            if temp >= 75000 or any(a != '0' for a in alarm):
              raise RuntimeError('health stop')
            samples.append({'temp_millic': temp, 'voltage_alarm': alarm})
            last = now
        elapsed = time.monotonic() - start
        results.append({'pair': pair + 1, 'algorithm': name, 'phase': args.phase, 'wall_s': elapsed,
                        'cpu_s': time.process_time() - cpu, 'bytes': count * len(DATA),
                        'mib_s': count * len(DATA) / 1048576 / elapsed, 'health': samples})
      finally:
        op.close()
        parent.close()
  print(json.dumps({'workload': 'af-alg-xts-64k-encrypt-v1', 'kernel': __import__('os').uname().release,
                    'ciphertext_equal_within_phase': True, 'ciphertext_sha256': __import__('hashlib').sha256(expected).hexdigest(), 'existing_root_changed': False,
                    'storage_io': False, 'firmware_throttle': None, 'energy': None,
                    'results': results}, indent=2))

if __name__ == '__main__':
  main()
