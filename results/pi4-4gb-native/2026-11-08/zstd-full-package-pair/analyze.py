#!/usr/bin/env python3
"""Recheck the preserved CLI rates, paired effects and health evidence."""
import gzip
import importlib.util
import json
import math
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location(
  'benchmark', ROOT / 'tools/pi-experiments/zstd-package-benchmark.py')
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)
summary = json.loads((HERE / 'summary.json').read_text())
records = [json.loads(p.read_text()) for p in HERE.glob('*/results-sanitized.json')]
assert len(records) == 6
contexts = []
count = 0
for path in HERE.glob('*/results-sanitized.json'):
  record = json.loads(path.read_text())
  assert record['status'] == 'complete'
  contexts.append((record['context'], record['providers'], record['loader'],
                   record['gate_sha256'], record['runner_sha256']))
  measured = [t for t in record['trials'] if t['phase'] == 'measured']
  assert len(measured) == 12
  assert len(record['trials']) == 14
  assert [t['variant'] for t in measured] == list(('O2', 'O3', 'O3', 'O2') * 3)
  assert [t['block'] for t in measured] == [b for b in range(6) for _ in range(2)]
  for trial in record['trials']:
    command = record['commands'][trial['command']]
    raw = b''.join((path.parent / command[k]).read_bytes() for k in ('stdout', 'stderr'))
    parsed = benchmark.parse_rates(raw.decode(errors='replace'), trial['input_bytes'])
    for key in ('input_bytes', 'compressed_bytes', 'compression_MB_s', 'decode_MB_s'):
      assert parsed[key] == trial[key], (path, key)
  unit = next(u for u in summary['units']
              if u['workload'] == record['measurement_protocol']['workload_unit'])
  for metric in ('compression_MB_s', 'decode_MB_s'):
    pairs = []
    for block in range(6):
      values = {t['variant']: t[metric] for t in measured if t['block'] == block}
      pairs.append((values['O3'] / values['O2'] - 1) * 100)
    expected = unit['metrics'][metric]
    assert pairs == expected['paired_O3_minus_O2_percent']
    assert math.isclose(statistics.median(pairs), expected['paired_median_percent'])
  assert unit['compressed_bytes_by_variant']['O2'] == unit['compressed_bytes_by_variant']['O3']
  with gzip.open(path.parent / 'health.jsonl.gz', 'rt') as stream:
    for line in stream:
      health = json.loads(line)
      assert max(health['temperatures_mC'].values()) < 70000
      assert health['native_voltage_alarms']
      assert all(v == '0' for v in health['native_voltage_alarms'].values())
  count += len(measured)
assert all(c == contexts[0] for c in contexts)
assert count == 72
print('PASS: 72 measured CLI calls, 12 excluded calibrations, balanced pairs, effects, sizes and health')
print('Exported boot identifiers are redacted; original identity is covered by the raw receipts.')
