#!/usr/bin/python3
"""Parent-only read-only GPIO observer; default performs no target reads."""
import argparse
import json
import os
from pathlib import Path
import time

PINCTRL = Path('/sys/kernel/debug/pinctrl/fe200000.gpio-pinctrl-bcm2711')
SCHEDULE = (0, .05, .10, .15, .20, .25, .30, .40, .50, .65, .80, 1, 1.5, 2, 4, 8, 11)
CAP = 128 * 1024


def read(path):
  # Only fixed debugfs GPIO/pinctrl and procfs identity files; never UART I/O.
  with path.open('rb') as source:
    raw = source.read(CAP + 1)
  if len(raw) > CAP:
    raise RuntimeError('Read cap exceeded: ' + str(path))
  return raw.decode('utf-8', errors='strict')


def snapshot():
  result = {}
  for name, path in [('pins', PINCTRL / 'pins'), ('mux', PINCTRL / 'pinmux-pins'),
                     ('gpio', Path('/sys/kernel/debug/gpio'))]:
    start = time.monotonic()
    value = read(path)
    if name != 'gpio':
      value = '\n'.join(line for line in value.splitlines()
                        if any(line.startswith(f'pin {pin} (') for pin in (30, 31, 32, 33)))
      if len(value.splitlines()) != 4:
        raise RuntimeError('Expected all four UART pins in ' + name)
    # Keep full GPIO text privately: controller headings identify BT_ON's chip.
    result[name] = {'start': start, 'end': time.monotonic(), 'text': value}
  return result


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--observe-actions', type=Path)
  parser.add_argument('--output', type=Path)
  args = parser.parse_args()
  if not args.observe_actions:
    print(json.dumps({'mode': 'offline plan', 'arm_timeout_seconds': 30,
                      'sample_offsets_seconds': SCHEDULE, 'window_seconds': 12,
                      'requires': 'parent-only existing UART capture; external timeout 45s',
                      'writes': 'exclusive new output JSONL only; no tracefs/sysfs writes'}))
    return
  if not args.output or not args.observe_actions.is_absolute() or not args.output.is_absolute():
    parser.error('Observation requires absolute actions and fresh output paths')
  if args.observe_actions.exists():
    parser.error('Actions path already exists: refuse stale capture')
  # Finite diagnostic wait, not a service. Output must be disk-backed and private.
  fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
  with os.fdopen(fd, 'w') as output:
    def emit(value):
      output.write(json.dumps(value) + '\n')
      output.flush()
    boot = read(Path('/proc/sys/kernel/random/boot_id')).strip()
    emit({'armed': time.monotonic(), 'boot_id': boot, 'pid': os.getpid()})
    until = time.monotonic() + 30
    start = None
    while time.monotonic() < until:
      try:
        actions = json.loads(read(args.observe_actions))
        starts = [a['monotonic'] for a in actions if a['action'] == 'trace-start']
        if len(starts) == 1:
          start = starts[0]
          break
      except (FileNotFoundError, json.JSONDecodeError):
        pass  # atomicity is not promised by the existing actions writer
      time.sleep(.01)
    if start is None or not 0 <= time.monotonic() - start < .25:
      raise RuntimeError('Missing/stale trace-start; no catch-up samples')
    for offset in SCHEDULE:
      delay = start + offset - time.monotonic()
      if delay > 0:
        time.sleep(delay)
      if time.monotonic() >= start + 12:
        raise RuntimeError('Observation window expired')
      sample = snapshot()
      emit({'offset': offset, 'trace_start': start, 'sample': sample})
      if any(item['end'] - item['start'] > .05 for item in sample.values()):
        raise RuntimeError('Read exceeded 50ms budget; stop observation')
      if read(Path('/proc/sys/kernel/random/boot_id')).strip() != boot:
        raise RuntimeError('Boot identity changed')
    emit({'finished': time.monotonic(), 'boot_id': boot})


if __name__ == '__main__':
  main()
