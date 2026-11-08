"""Tests helper decisions/cleanup only; no tracefs, sysfs or physical evidence."""
import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('bttrace', ROOT / 'tools/pi-experiments/bluetooth-transport-trace.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class ControlTests(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.capture = m.Capture(pathlib.Path(self.temp.name))

  def test_required_ambiguity_refused(self):
    found = {name: ['[hci_uart]'] for name in m.REQUIRED}
    found['bcm_recv'].append('[other]')
    with self.assertRaisesRegex(RuntimeError, 'ambiguous'):
      m.select(found)

  def test_adapter_discovered_before_selection(self):
    found = {name: ['[hci_uart]'] for name in m.REQUIRED}
    self.assertNotIn('ttyport_write_buf', m.select(found))
    found['ttyport_write_buf'] = [None]
    self.assertIn('ttyport_write_buf', m.select(found))
    found['serial8250_tx_chars'] = [None]
    self.assertNotIn('serial8250_tx_chars', m.select(found))

  def test_restore_only_if_owned_unbind_and_detached(self):
    self.capture.unbind_attempted = True
    with patch.object(m, 'binding', return_value=None), patch.object(self.capture, 'sysfs') as syscall:
      self.capture.cleanup()
    syscall.assert_called_once_with('bind', 4)

  def test_foreign_binding_never_touched(self):
    self.capture.unbind_attempted = True
    with patch.object(m, 'binding', return_value='/foreign'), patch.object(self.capture, 'sysfs') as syscall:
      self.capture.cleanup()
    syscall.assert_not_called()
    self.assertTrue(self.capture.errors)

  def test_untouched_detach_never_rebound(self):
    with patch.object(m, 'binding', return_value=None), patch.object(self.capture, 'sysfs') as syscall:
      self.capture.cleanup()
    syscall.assert_not_called()

  def test_stop_failure_does_not_skip_binding_restore(self):
    self.capture.created = True
    self.capture.unbind_attempted = True
    with patch.object(m, 'write', side_effect=OSError('injected')), patch.object(m, 'binding', return_value=None), patch.object(self.capture, 'sysfs') as syscall:
      self.capture.cleanup()
    syscall.assert_called_once_with('bind', 4)

  def test_uninterruptible_child_prevents_competing_bind(self):
    self.capture.child = Mock()
    self.capture.child.wait.side_effect = m.subprocess.TimeoutExpired('injected', 1)
    self.capture.unbind_attempted = True
    with patch.object(m, 'binding', return_value=None), patch.object(self.capture, 'sysfs') as syscall:
      self.capture.cleanup()
    syscall.assert_not_called()
    self.assertTrue(self.capture.errors)

  def test_exact_owned_instance_only(self):
    self.capture.created = True
    with patch.object(m, 'write') as writes, patch.object(m, 'binding', return_value=str(m.DRIVER)), patch.object(m, 'bound_copy', return_value=False), patch.object(m, 'read', return_value='stats'), patch.object(pathlib.Path, 'rmdir') as remove:
      self.capture.cleanup()
    self.assertEqual([str(call.args[0]) for call in writes.call_args_list], [str(self.capture.instance / 'tracing_on'), str(self.capture.instance / 'current_tracer')])
    remove.assert_called_once()

  def test_setup_preserves_absent_top_level_options(self):
    # Exact7.3 omits global-only controls from instance options. Refuse fake
    # tracefs file creation and stop before any driver operation.
    def trace_write(path, value):
      if path.name in ('record-cmd', 'record-tgid'):
        raise PermissionError('global-only option has no instance control')
    def trace_read(path, *args):
      return 'bcm_open' if path.name == 'set_ftrace_filter' else 'function'
    with patch.object(pathlib.Path, 'mkdir'), patch.object(m, 'write', side_effect=trace_write) as writes, patch.object(m, 'read', side_effect=trace_read), patch.object(m, 'binding', return_value='/foreign'), patch.object(self.capture, 'sysfs') as syscall:
      with self.assertRaisesRegex(RuntimeError, 'Binding changed'):
        self.capture.run(['bcm_open:mod:hci_uart'])
    syscall.assert_not_called()
    self.assertFalse(any(call.args[0].name in ('record-cmd', 'record-tgid') for call in writes.call_args_list))

  def test_output_cap(self):
    src = pathlib.Path(self.temp.name) / 'source'
    src.write_bytes(b'12345678')
    dst = pathlib.Path(self.temp.name) / 'copy'
    self.assertTrue(m.bound_copy(src, dst, 4))
    self.assertEqual(dst.read_bytes(), b'1234')

if __name__ == '__main__':
  unittest.main(verbosity=2)
