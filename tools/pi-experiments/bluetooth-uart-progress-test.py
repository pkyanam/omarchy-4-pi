#!/usr/bin/python3
"""Offline safety regression checks; never accesses a Pi or tracefs."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('uart', Path(__file__).with_name('bluetooth-uart-progress.py'))
uart = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uart)
BTF_PATH = Path(__file__).resolve().parents[2] / 'build/upstream-pi/stable-4.5/bt-scalar-trace-candidate/running-vmlinux.btf'


class Safety(unittest.TestCase):
  def test_changed_btf_refused_before_decode(self):
    with tempfile.TemporaryDirectory() as tmp:
      p = Path(tmp) / 'wrong.btf'
      p.write_bytes(b'wrong kernel')
      with self.assertRaisesRegex(RuntimeError, 'BTF hash differs'):
        uart.evidence(p)

  @unittest.skipUnless(BTF_PATH.exists(), 'Parent exact BTF capture unavailable')
  def test_exact_capture_derives_scalars_and_refuses_pointer(self):
    btf = uart.BTF(BTF_PATH)
    layout = uart.evidence(BTF_PATH)
    self.assertEqual(layout['btf_sha256'], hashlib.sha256(BTF_PATH.read_bytes()).hexdigest())
    self.assertEqual(layout['fields']['line']['bytes'], 4)
    with self.assertRaisesRegex(RuntimeError, 'Only integer RAM scalars'):
      btf.scalar('uart_port', 'membase')
    # Ensure the generated line fetch actually uses the verified BTF offset,
    # rather than a source-assumed ABI constant; no register pointer export.
    for _, _, _, _, fields in uart.probes(layout):
      line = next(f for f in fields if f[0] == 'line')
      self.assertEqual(line[1], '+' + str(layout['fields']['line']['offset']) + '(%x0):u32')
      self.assertTrue(all(f[1].startswith('+') or f[0] == 'active' for f in fields))

  def test_identity_cannot_be_assumed_from_device_path(self):
    with tempfile.TemporaryDirectory() as tmp:
      p = Path(tmp) / 'identity.json'
      p.write_text(json.dumps({'device_path': uart.DEVICE_PATH, 'line': 1}))
      with self.assertRaisesRegex(RuntimeError, 'current-boot'):
        uart.load_identity(p)
      value = {'device_path': uart.DEVICE_PATH, 'line': 1,
               'proof': 'current-boot UART registration maps fe215040.serial to ttyS1',
               'boot_id': '11111111-1111-1111-1111-111111111111',
               'source_evidence_sha256': 'a' * 64}
      p.write_text(json.dumps(value))
      self.assertEqual(uart.load_identity(p), value)
      value['extra'] = 'unreviewed data'
      p.write_text(json.dumps(value))
      with self.assertRaises(RuntimeError):
        uart.load_identity(p)
      del value['extra']
      value['line'] = 0  # numeric dereference faults can yield zero; never match it
      p.write_text(json.dumps(value))
      with self.assertRaises(RuntimeError):
        uart.load_identity(p)

  def test_live_modes_refuse_missing_identity_before_import_or_side_effect(self):
    for mode in ('--execute', '--validate-probes'):
      with patch('sys.argv', ['candidate', mode]), contextlib.redirect_stderr(io.StringIO()):
        with self.assertRaises(SystemExit) as e:
          uart.run()
        self.assertEqual(e.exception.code, 2)

  def test_live_cannot_substitute_saved_btf(self):
    with patch('sys.argv', ['candidate', '--validate-probes', '--identity', 'unused', '--btf', 'saved']), contextlib.redirect_stderr(io.StringIO()):
      with self.assertRaises(SystemExit) as e:
        uart.run()
      self.assertEqual(e.exception.code, 2)


if __name__ == '__main__':
  unittest.main()
