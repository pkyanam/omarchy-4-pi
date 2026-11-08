#!/usr/bin/env python3
"""Pure source-level regression checks: no server, browser or Linux device access."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('trial', Path(__file__).with_name('thp-browser-trial.py'))
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)


class SourceChecks(unittest.TestCase):
  def test_unknown_mode_is_not_baseline(self):
    self.assertIsNone(trial.selected(None))
    self.assertIsNone(trial.selected('always madvise never'))
    self.assertEqual(trial.selected('always [madvise] never'), 'madvise')

  def test_process_names_with_parentheses_and_grandchildren(self):
    # /proc stat comm can contain spaces and parentheses; split only after last ).
    records = {'/proc/10/stat': '10 (browser (main)) S 1 10',
               '/proc/11/stat': '11 (zygote) S 10 10',
               '/proc/12/stat': '12 (renderer) S 11 10',
               '/proc/20/stat': '20 (personal browser) S 1 20'}
    with patch.object(trial.Path, 'glob', return_value=[Path(p) for p in records]), patch.object(trial, 'read', side_effect=lambda p: records.get(str(p))):
      self.assertEqual(trial.process_tree(10), [10, 11, 12])

  def test_rss_read_failure_is_unknown(self):
    with patch.object(trial, 'process_tree', return_value=[10]), patch.object(trial, 'read', return_value=None):
      self.assertIsNone(trial.rss_sample(10)['processes']['10'])

  def test_trace_loss_rejected_before_output(self):
    class Browser:
      events = [{'method': 'Tracing.tracingComplete', 'params': {'dataLossOccurred': True}}]
      def call(self, *_):
        return {}
    with tempfile.TemporaryDirectory() as directory:
      with self.assertRaisesRegex(RuntimeError, 'data lost'):
        trial.trace_save(Browser(), Path(directory) / 'trace.json')
      self.assertFalse((Path(directory) / 'trace.json').exists())


if __name__ == '__main__':
  unittest.main()
