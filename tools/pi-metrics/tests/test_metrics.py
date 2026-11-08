import base64
import copy
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('metrics', ROOT / 'metrics.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class MetricsTests(unittest.TestCase):
  def test_big_endian_revision_and_no_ram_default(self):
    self.assertEqual(m.revision(bytes.fromhex('00c03115')), ('00c03115', 4096))
    self.assertEqual(m.revision(bytes.fromhex('00d03115'))[1], 8192)
    self.assertIsNone(m.revision(bytes.fromhex('00000002'))[1])
    with self.assertRaises(ValueError):
      m.revision(b'')

  def test_throttle_current_history_and_malformed(self):
    self.assertEqual(m.throttle('throttled=0x50005\n'), 0x50005)
    self.assertEqual(m.throttle('throttled=0x0'), 0)
    for bad in ('', '0x0', 'throttled=garbage', 'throttled=0x0\nextra'):
      with self.assertRaises(ValueError):
        m.throttle(bad)

  def test_crypto_decimal_bytes_not_kibibytes(self):
    self.assertEqual(m.openssl_rate('+F:25:aes-256-cbc:1048576.00'), 1)
    for bad in ('', '+F:1:sha256:nan', '+F:1:sha256:0', '+F:1:sha256:1:2'):
      with self.assertRaises(ValueError):
        m.openssl_rate(bad)

  def test_matching_config_only(self):
    with tempfile.TemporaryDirectory() as tmp:
      root = Path(tmp)
      wrong = root/'usr/lib/modules/old/build'
      wrong.mkdir(parents=True)
      (wrong/'.config').write_text('CONFIG_HZ=999\nCONFIG_LTO_CLANG=y')
      with self.assertRaises(FileNotFoundError):
        m.kernel_config(root, 'running')
      build = root/'usr/lib/modules/running/build'
      (build/'include/config').mkdir(parents=True)
      (build/'.config').write_text('CONFIG_HZ=1000\n# CONFIG_LTO_CLANG is not set')
      (build/'include/config/kernel.release').write_text('old')
      with self.assertRaises(ValueError):
        m.kernel_config(root, 'running')
      (build/'include/config/kernel.release').write_text('running\n')
      config, source = m.kernel_config(root, 'running')
      self.assertEqual(m.config_values(config)['CONFIG_LTO_CLANG'], 'n')
      (root/'proc').mkdir()
      (root/'proc/config.gz').write_bytes(gzip.compress(b'CONFIG_HZ=250'))
      self.assertEqual(m.kernel_config(root, 'running')[0], 'CONFIG_HZ=250')

  def test_missing_and_permission_are_not_zero(self):
    with patch.object(m, 'read', side_effect=PermissionError):
      self.assertEqual(m.file_probe('/no', 'kHz', int)['status'], 'permission_denied')
    with patch.object(m, 'read', return_value='nonsense'):
      self.assertIsNone(m.file_probe('/no', 'kHz', int)['value'])
    self.assertEqual(m.file_probe('/definitely-missing-pi-metrics')['status'], 'unavailable')

  def test_no_unprivileged_success(self):
    with patch.object(m.os, 'geteuid', return_value=1000):
      with self.assertRaises(ValueError):
        m.collect({})

  def test_ssh_injection_and_transport(self):
    for host in ('-oProxyCommand=evil', 'host;touch /tmp/x', 'user@host', 'host\nother'):
      with self.assertRaises(ValueError):
        m.ssh_argv(host, 'owner', '/key', '/hosts', [])
    argv = m.ssh_argv('pi.example', 'owner', '/key', '/hosts', ['--metadata-b64', 'YWJj'])
    self.assertIn('StrictHostKeyChecking=yes', argv)
    self.assertIn('BatchMode=yes', argv)
    self.assertEqual(shlex.split(argv[-1]), ['sudo', '-n', '--', '/usr/bin/python3', '-I', '-', 'probe', '--metadata-b64', 'YWJj'])
    # Actual subprocess transport: stdin remains code, metadata survives quotes/newlines.
    value = 'trial "quote"\n$(false); label'
    encoded = base64.b64encode(json.dumps(value).encode()).decode()
    proc = subprocess.run([sys.executable, '-I', '-', encoded], input='import sys,json,base64\nprint(json.loads(base64.b64decode(sys.argv[1])))', text=True, capture_output=True, check=True)
    self.assertEqual(proc.stdout.rstrip('\n'), value)

  def sample(self):
    meta = dict(cohort='pi4-4gb-v2', label='baseline', experiment='idle', trial='1', conditions='cool desktop', candidate='unknown', probe_sha256='a'*64, transport='ssh-key-strict-hostkey-sudo-n')
    probes = {name:m.unknown('text','fixture','not measured') for name in ['kernel.release','board.revision','board.nominal_ram','security.kpti_runtime','build.installed_compiler_flags']}
    probes['collector.euid'] = m.result(0,'uid','geteuid')
    for name, unit in [('board.revision','hex'), ('board.nominal_ram','MiB'), ('security.kpti_runtime','boolean')]:
      probes[name]['unit'] = unit
    tele = {name:m.unknown('text','fixture','not measured') for name in ['firmware.throttled_raw','uptime','loadavg','pressure.cpu','pressure.memory','pressure.io']}
    tele['firmware.throttled_raw']['unit'] = 'bitmask'
    tele['uptime']['unit'] = 'seconds'
    return dict(schema_version=2, tool_version=m.VERSION, sample_id='12345678-1234-4234-9234-123456789abc', started_utc='2026-11-08T12:00:00+00:00', ended_utc='2026-11-08T12:00:01+00:00', metadata=meta, probes=probes, before=tele, after=copy.deepcopy(tele))

  def test_schema_rejects_legacy_nan_bad_status_traversal_extra(self):
    sample = self.sample()
    m.validate_sample(sample)
    mutations = [lambda s:s.update(schema_version=1), lambda s:s['metadata'].update(cohort='../escape'), lambda s:s.update(password='secret'), lambda s:s['probes']['collector.euid'].update(value=float('nan')), lambda s:s['probes']['collector.euid'].update(status='unavailable'), lambda s:s['metadata'].pop('label'), lambda s:s['probes'].pop('kernel.release')]
    for mutate in mutations:
      bad = copy.deepcopy(sample)
      mutate(bad)
      with self.assertRaises(ValueError):
        m.validate_sample(bad)

  def test_controller_refuses_failures_and_persists_metadata(self):
    from types import SimpleNamespace
    with tempfile.TemporaryDirectory() as tmp:
      argv = ['metrics.py', 'record']
      for key, value in dict(host='pi.example', user='owner', identity='/key', known_hosts='/hosts', cohort='pi4-4gb-v2', label='quoted "label"', experiment='idle', trial='01', conditions='cool', candidate='unknown', out=tmp).items():
        argv.extend(['--' + key.replace('_', '-'), value])
      def response(command, **kwargs):
        self.assertEqual(kwargs['input'], (ROOT/'metrics.py').read_bytes())
        remote = shlex.split(command[-1])
        meta = json.loads(base64.b64decode(remote[remote.index('--metadata-b64')+1]))
        sample = self.sample()
        sample['metadata'] = meta
        return SimpleNamespace(stdout=json.dumps(sample).encode())
      with patch.object(sys, 'argv', argv), patch.object(m.subprocess, 'run', side_effect=subprocess.CalledProcessError(255, 'ssh')):
        with self.assertRaises(subprocess.CalledProcessError):
          m.main()
      self.assertEqual(list(Path(tmp).rglob('*.json')), [])
      with patch.object(sys, 'argv', argv), patch.object(m.subprocess, 'run', return_value=SimpleNamespace(stdout=b'banner\n{}')):
        with self.assertRaises(ValueError):
          m.main()
      self.assertEqual(list(Path(tmp).rglob('*.json')), [])
      with patch.object(sys, 'argv', argv), patch.object(m.subprocess, 'run', side_effect=response):
        m.main()
      saved = next(Path(tmp).rglob('*.json'))
      self.assertEqual(json.loads(saved.read_text())['metadata']['label'], 'quoted "label"')
      self.assertEqual(saved.stat().st_mode & 0o777, 0o600)

  def test_real_local_openssl_protocol_when_available(self):
    import shutil
    if not shutil.which('openssl'):
      self.skipTest('openssl unavailable')
    binary = '/opt/homebrew/opt/openssl@3/bin/openssl' if Path('/opt/homebrew/opt/openssl@3/bin/openssl').exists() else shutil.which('openssl')
    if not m.run([binary, 'version']).stdout.startswith('OpenSSL 3.'):
      self.skipTest('OpenSSL 3 required; LibreSSL is unsupported')
    proc = m.run([binary,'speed','-mr','-elapsed','-seconds','1','-bytes','8192','-evp','sha256'])
    self.assertGreater(m.openssl_rate(proc.stdout+'\n'+proc.stderr), 0)
    proc = m.run([binary,'speed','-mr','-elapsed','-seconds','1','-bytes','8192','-evp','aes-256-cbc'])
    self.assertGreater(m.openssl_rate(proc.stdout+'\n'+proc.stderr), 0)

  def test_collection_on_unavailable_probe_host_stays_unknown(self):
    with patch.object(m.sys, 'platform', 'linux'), patch.object(m.os, 'geteuid', return_value=0):
      sample = m.collect(self.sample()['metadata'])
    m.validate_sample(sample)
    self.assertEqual(sample['probes']['security.kpti_runtime']['status'], 'not_measured')
    self.assertIsNone(sample['probes']['build.installed_compiler_flags']['value'])

  def test_legacy_evidence_is_six_rows(self):
    import csv
    with (ROOT/'legacy/pi4-v1.csv').open() as fh:
      rows = list(csv.DictReader(fh))
    self.assertEqual(len(rows), 6)
    self.assertEqual(rows[0]['board_revision'], '1531c000')


if __name__ == '__main__':
  unittest.main()
