#!/usr/bin/python3
"""Local control-flow regressions; never access tracefs or a device."""
import errno
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('scalar', Path(__file__).with_name('bluetooth-scalar-trace.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Controls(unittest.TestCase):
  def test_command_io_uses_existing_fd_without_append_seek_or_truncation(self):
    # Audit the real file open in a child, then check actual parser-command bytes.
    # Original Path.open("a") fails this contract before its write.
    code = r'''
import importlib.util, os, pathlib, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("scalar", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
p = pathlib.Path(sys.argv[2])
m.base.TRACE = p
opens = []
def audit(event, args):
  if event == "open" and args[0] == str(p / "kprobe_events"):
    path, mode, flags = args
    assert mode is None, "Raw command fd required: append streams seek to EOF"
    assert not flags & (os.O_TRUNC | os.O_CREAT), "Must preserve existing control file"
    opens.append(flags)
sys.addaudithook(audit)
m.append_probe("p:owned/write ttyport_write_buf requested=%x2:u64")
assert len(opens) == 1
'''
    with tempfile.TemporaryDirectory() as directory:
      control = Path(directory) / 'kprobe_events'
      control.touch()
      result = subprocess.run([sys.executable, '-I', '-c', code, str(Path(m.__file__).resolve()), directory], capture_output=True, text=True)
      self.assertEqual(result.returncode, 0, result.stderr)
      self.assertEqual(control.read_bytes(), b'p:owned/write ttyport_write_buf requested=%x2:u64\n')

  def test_command_io_short_or_failed_write_closes_without_retry(self):
    for outcome in [2, OSError(errno.EINVAL, 'parser refusal')]:
      with self.subTest(outcome=outcome), patch.object(m.os, 'open', return_value=42), patch.object(m.os, 'write', side_effect=outcome if isinstance(outcome, OSError) else None, return_value=outcome) as write, patch.object(m.os, 'close') as close:
        with self.assertRaises((OSError, RuntimeError)):
          m.append_probe('p:owned/write ttyport_write_buf requested=%x2:u64')
        write.assert_called_once()
        close.assert_called_once_with(42)

  def test_busy_tracing_refusal(self):
    state = {"kernel": m.base.KERNEL, "machine": "aarch64", "taint": "0", "binding": str(m.base.DRIVER), "current_tracer": "nop", "events/enable": "0", "instances": [], "kprobe_events": "", "dynamic_events": ""}
    for key, value in [("current_tracer", "function"), ("events/enable", "1"), ("instances", ["other"]), ("kprobe_events", "p:other/event other")]:
      with self.subTest(key=key), self.assertRaises(RuntimeError):
        m.base.validate(state | {key: value})

  def test_signed_return_format_and_width_rejection(self):
    fields = [('accepted', '$retval:s64', 8, 1)]
    fmt = 'name: written\nID: 7\n field:s64 accepted; offset:24; size:8; signed:1;\n'
    self.assertEqual(m.check_format(fmt, fields), m.check_format(fmt.replace('7', '9'), fields))
    with self.assertRaises(RuntimeError):
      m.check_format(fmt.replace('signed:1', 'signed:0'), fields)
    with self.assertRaises(RuntimeError):
      m.check_format(fmt.replace('size:8', 'size:4'), fields)

  def test_extra_pointer_field_refused(self):
    with self.assertRaises(RuntimeError):
      m.check_format('field:void * data; offset:8; size:8; signed:0;', [])

  def test_partial_install_cleans_only_journal_even_after_write_error(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      key = cap.group + '/write'
      command = f'p:{key} ttyport_write_buf requested=%x2:u64'
      cap.pending = [key]
      cap.commands[key] = command
      with patch.object(m, 'definitions', return_value={key: command, 'foreign/event': 'p:foreign/event other'}), patch.object(m, 'append_probe') as remove, patch.object(m.base, 'binding', return_value=str(m.base.DRIVER)), patch.object(cap, 'sysfs') as bind:
        self.assertEqual(cap.cleanup(), [])
        remove.assert_called_once_with('-:' + key)
        bind.assert_not_called()

  def test_changed_definition_not_deleted(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      key = cap.group + '/write'
      cap.pending = [key]
      cap.commands[key] = 'old'
      cap.installed[key] = 'old'
      with patch.object(m, 'definitions', return_value={key: 'changed'}), patch.object(m, 'append_probe') as remove, patch.object(m.base, 'binding', return_value=str(m.base.DRIVER)):
        self.assertTrue(cap.cleanup())
        remove.assert_not_called()

  def test_uninterruptible_worker_prevents_competing_bind(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      cap.unbind_attempted = True
      cap.child = Mock()
      cap.child.wait.side_effect = subprocess.TimeoutExpired('sysfs', 1)
      with patch.object(m.base, 'binding', return_value=None), patch.object(cap, 'sysfs') as bind:
        self.assertTrue(cap.cleanup())
        bind.assert_not_called()
        self.assertIsNotNone(cap.child)

  def test_worker_kill_error_does_not_skip_probe_cleanup(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      cap.child = Mock()
      cap.child.kill.side_effect = OSError("cannot kill")
      cap.unbind_attempted = True
      key = cap.group + '/write'
      cap.pending = [key]
      cap.commands[key] = 'owned'
      with patch.object(m, 'definitions', return_value={key: 'owned'}), patch.object(m, 'append_probe') as remove, patch.object(m.base, 'binding', return_value=None), patch.object(cap, 'sysfs') as bind:
        self.assertTrue(cap.cleanup())
        remove.assert_called_once_with('-:' + key)
        bind.assert_not_called()

  def test_sysfs_worker_is_owned_before_wait_timeout(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      worker = Mock(pid=123)
      worker.wait.side_effect = subprocess.TimeoutExpired('sysfs', 2)
      with patch.object(m.subprocess, 'Popen', return_value=worker) as launch:
        with self.assertRaises(RuntimeError):
          cap.sysfs('unbind', 2)
        self.assertIs(cap.child, worker)
        self.assertTrue(cap.unbind_attempted)
        code = launch.call_args.args[0][3]
        compile(code, '<owned-worker>', 'exec')
        self.assertEqual(__import__('json').loads((Path(directory) / 'worker.json').read_text())['pid'], 123)

  def test_failed_bind_never_retried(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      cap.unbind_attempted = cap.bind_attempted = True
      with patch.object(m.base, 'binding', return_value=None), patch.object(cap, 'sysfs') as bind:
        self.assertTrue(cap.cleanup())
        bind.assert_not_called()

  def test_unbind_failure_recovery_and_foreign_binding_protection(self):
    for current, expect in [(None, True), ('/foreign', False), (str(m.base.DRIVER), False)]:
      with tempfile.TemporaryDirectory() as directory:
        cap = m.Capture(Path(directory))
        cap.unbind_attempted = True
        with patch.object(m.base, 'binding', return_value=current), patch.object(cap, 'sysfs') as bind:
          cap.cleanup()
          self.assertEqual(bind.called, expect)

  def test_install_failure_runs_journal_cleanup_without_binding(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      cap.instance = MagicMock()
      cap.instance.name = 'instance'
      found = {symbol: [f'[{module}]' if module else None] for _, _, symbol, module, _ in m.PROBES}
      events = {}
      def append(command):
        if command.startswith('-:'):
          events.pop(command[2:])
        else:
          key = command.split()[0].split(':')[1]
          events[key] = command
          raise OSError(errno.EINVAL, 'write failed after commit')
      with patch.object(m.base, 'symbols', return_value=found), patch.object(m.base, 'write'), patch.object(m.base, 'read', return_value=''), patch.object(m.base, 'bound_copy', return_value=False), patch.object(m.base, 'binding', return_value=str(m.base.DRIVER)), patch.object(m, 'definitions', side_effect=lambda: dict(events)), patch.object(m, 'append_probe', side_effect=append), patch.object(cap, 'sysfs') as bind:
        with self.assertRaises(OSError):
          cap.install()
        diagnostic = __import__('json').loads((Path(directory) / 'registration-failure.json').read_text())
        self.assertEqual(diagnostic['errno'], errno.EINVAL)
        self.assertIn('requested=%x2:u64', diagnostic['command'])
        self.assertEqual(diagnostic['tracefs_error_log'], '')
        cap.cleanup()
        self.assertEqual(events, {})
        bind.assert_not_called()

  def test_state_change_before_rebind_never_calls_sysfs(self):
    with tempfile.TemporaryDirectory() as directory:
      cap = m.Capture(Path(directory))
      with patch.object(m.base, 'write'), patch.object(m, 'shared_state', return_value={'changed': True}), patch.object(cap, 'sysfs') as bind:
        with self.assertRaises(RuntimeError):
          cap.run_window({})
        bind.assert_not_called()


if __name__ == '__main__':
  unittest.main()
