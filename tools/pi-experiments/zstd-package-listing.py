#!/usr/bin/env python3
"""Parent-only bounded bsdtar listing follow-up; self-test executes no applications."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import signal
import statistics
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
BASE_PATH = Path(__file__).with_name('zstd-package-benchmark.py')
BASE_SHA = 'bf40ba15e4eb370c35f8fc2a525dd87033748a0d4df27d457f72fbad6e365bf0'
ARCHIVE_SHA = '2164fb79c02442b9047166b07f1667558f1674c2ccf345d38b9f7e10e97ef8d8'
ARCHIVE_BYTES = 181666855
BSDTAR = Path('/usr/bin/bsdtar')
spec = importlib.util.spec_from_file_location('listing_base', BASE_PATH)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
require = base.require


def schedule():
  return [(block, name) for block in range(6)
          for name in (('O3', 'O2') if block % 2 == 0 else ('O2', 'O3'))]


def listing(raw):
  # Kernel package member names have no embedded newline; retain exact bytes too.
  paths = raw.split(b'\n')
  require(raw.endswith(b'\n') and all(paths[:-1]), 'empty or unterminated archive path')
  require(0 < len(raw) <= 2 * 1024**2 and b'\0' not in raw, 'invalid/oversized listing')
  return {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw),
          'nonempty_paths': len(paths) - 1}


def project(costs):
  require(len(costs) == 2 and all(c > 0 for c in costs), 'two fresh calibrations required')
  return max(costs) * len(schedule()) * 1.15


class ListingRunner(base.Runner):
  def __init__(self, args):
    super().__init__(args)
    self.report.update(application_protocol_version=1, runner_sha256=base.sha(__file__),
      base_runner_sha256=base.sha(BASE_PATH), pair_comparison='system bsdtar/libarchive; full O2/O3 libzstd',
      wall_scope='complete child lifecycle: loader, archive read/decode, metadata traversal and stdout file writes; includes sampling wait',
      cache_scope='warm reads by hashing and prior listings; no flush or cold-I/O claim')
    self.archive = args.archive.resolve()
    self.libdirs = {}

  def input_identity(self):
    st = self.archive.stat()
    require(self.archive.is_file() and st.st_size == ARCHIVE_BYTES, 'wrong archive size/type')
    base.check_hash(self.archive, ARCHIVE_SHA)
    return {'path': str(self.archive), 'bytes': st.st_size, 'sha256': ARCHIVE_SHA,
            'device': st.st_dev, 'inode': st.st_ino, 'mtime_ns': st.st_mtime_ns}

  def command(self, name, args, binary='zstd'):
    # Base provenance still uses its original full package CLI/library paths.
    return super().command(name, args, binary)

  def app_command(self, name, *args):
    return [base.LOADER, '--library-path', self.libdirs[name], BSDTAR, *args]

  def stable(self):
    super().stable()
    base.check_hash(BSDTAR, self.report['bsdtar_sha256'])
    require(self.call(['/usr/bin/pacman', '-Q', 'libarchive'], monitor=False).decode()
            == self.report['libarchive_package'], 'libarchive package drift')
    require(self.input_identity() == self.report['archive'], 'source archive drift')
    for name, directory in self.libdirs.items():
      require(sorted(p.name for p in directory.iterdir()) == ['libzstd.so.1'], 'isolated path drift')
      base.check_hash(directory / 'libzstd.so.1', base.LIB_HASHES[name])
    used = sum(p.stat().st_size for p in self.out.rglob('*') if p.is_file() and not p.is_symlink())
    require(used < 128 * 1024**2, 'evidence exceeds 128 MiB allowance')
    require(shutil.disk_usage(self.out).free >= 512 * 1024**2, '512 MiB free reserve required')
    self.health()  # Hashing/guards also consume the original deadline.

  def verify(self):
    base.check_hash(BASE_PATH, BASE_SHA)  # No silent changes to inherited trust/health gates.
    require(self.args.cpu == 2, 'this protocol requires CPU2')
    require(shutil.disk_usage(self.out).free >= 640 * 1024**2,
            '512 MiB free reserve plus 128 MiB evidence headroom required')
    super().verify()
    native = json.loads(self.args.native_gate.read_text())
    require(native['mode'] == 'gate' and native['status'] == 'complete'
            and native['measurement_protocol_version'] == 3, 'complete native v3 gate required')
    require(native['runner_sha256'] == BASE_SHA, 'native gate runner mismatch')
    for key in ('manifest_sha256', 'context', 'providers', 'loader'):
      require(native[key] == self.report[key], f'fresh native gate context mismatch: {key}')
    self.report['native_gate_sha256'] = base.sha(self.args.native_gate)
    self.report['archive'] = self.input_identity()
    self.report['bsdtar_sha256'] = base.sha(BSDTAR)
    self.report['libarchive_package'] = self.call(['/usr/bin/pacman', '-Q', 'libarchive']).decode()
    header = self.call(['/usr/bin/readelf', '-h', BSDTAR]).decode()
    require('AArch64' in header and 'DYN' in header, 'bsdtar must be native AArch64 PIE')
    program = self.call(['/usr/bin/readelf', '-l', BSDTAR]).decode()
    interpreter = re.search(r'Requesting program interpreter:\s*(\S+)\]', program)
    require(interpreter and Path(interpreter[1]).resolve() == base.LOADER.resolve(), 'actual ELF loader mismatch')
    needed = self.call(['/usr/bin/readelf', '-d', BSDTAR]).decode()
    require('[libarchive.so.' in needed, 'bsdtar must dynamically depend on libarchive')
    self.call(['/usr/bin/readelf', '-V', BSDTAR])
    self.call([base.LOADER, '--verify', BSDTAR])
    system = self.call([base.LOADER, '--list', BSDTAR]).decode()
    system_paths = base.loader_paths(system, Path('/usr/lib'))
    self.report['providers']['system/bsdtar'] = self.fingerprints(system_paths)
    archive_providers = {k: p for k, p in system_paths.items() if k.startswith('libarchive.so.')}
    require(len(archive_providers) == 1, 'one system libarchive provider required')
    archive_lib = next(iter(archive_providers.values()))
    require('[libzstd.so.1]' in self.call(['/usr/bin/readelf', '-d', archive_lib]).decode(),
            'libarchive must dynamically depend on libzstd')
    self.call(['/usr/bin/readelf', '-V', archive_lib])
    for name in base.NAMES:
      # Only this package's full normal-ABI libzstd is exposed to the application.
      directory = self.tmp / ('lib-' + name)
      directory.mkdir()
      (directory / 'libzstd.so.1').symlink_to(self.bundle / name / 'root' / base.LIB)
      self.libdirs[name] = directory
      trace = self.call([base.LOADER, '--library-path', directory, '--list', BSDTAR]).decode()
      paths = base.loader_paths(trace, directory)
      require({k: p for k, p in paths.items() if k != 'libzstd.so.1'} ==
              {k: p for k, p in system_paths.items() if k != 'libzstd.so.1'}, 'foreign application dependencies')
      base.check_hash(paths['libzstd.so.1'], base.LIB_HASHES[name])
      self.report['providers'][name + '/bsdtar'] = self.fingerprints(paths)
      self.call(self.app_command(name, '--version'))
    self.report['application_protocol'] = {'orders': ['BA', 'AB'] * 3, 'A': 'O2', 'B': 'O3',
      'schedule': [{'block': b, 'variant': n} for b, n in schedule()],
      'calibration_order': ['O3', 'O2'], 'deadline_s': 300, 'measured_calls': 12,
      'cli': '/usr/bin/bsdtar -tf FIXED_ARCHIVE', 'stock_role': 'correctness reference only',
      'projection': 'max(two fresh lifecycle costs) * 12 * 1.15'}
    self.report['trials'] = []
    self.stable()
    self.persist()

  @staticmethod
  def fingerprints(paths):
    return {k: {'path': str(p), 'sha256': base.sha(p)} for k, p in paths.items()}

  def trial(self, name, phase, block=-1):
    start = time.monotonic()
    self.stable()
    while max(self.health()['temperatures_mC'].values()) > 52000:
      time.sleep(.5)
    self.stable()
    raw = self.call(self.app_command(name, '-tf', self.archive))
    idx = len(self.report['commands']) - 1
    actual = listing(raw)
    trial = {'variant': name, 'phase': phase, 'block': block, 'command': idx, 'listing': actual}
    self.report['trials'].append(trial)
    self.persist()
    require(not (self.out / self.report['commands'][idx]['stderr']).read_bytes(), 'bsdtar warning/error')
    if 'expected_listing' in self.report:
      require(actual == self.report['expected_listing'], 'listing hash/bytes/path-count mismatch')
    else:
      require(name == 'stock' and phase == 'correctness', 'stock reference required first')
      self.report['expected_listing'] = actual
    self.stable()
    return time.monotonic() - start

  def gate(self):
    # Fresh actual application correctness, in addition to the full native gate.
    for name in base.NAMES:
      self.trial(name, 'correctness')

  def bench(self):
    gate = json.loads(self.args.gate.read_text())
    require(gate['mode'] == 'gate' and gate['status'] == 'complete', 'application gate incomplete')
    for key in ('runner_sha256', 'base_runner_sha256', 'manifest_sha256', 'native_gate_sha256',
                'context', 'providers', 'loader', 'archive', 'bsdtar_sha256', 'libarchive_package'):
      require(gate[key] == self.report[key], f'application gate mismatch: {key}')
    self.report['gate_sha256'] = base.sha(self.args.gate)
    self.report['expected_listing'] = gate['expected_listing']
    costs = [self.trial(n, 'calibration') for n in ('O3', 'O2')]
    remaining = self.deadline - time.monotonic()
    self.report['calibration'] = {'lifecycle_costs_s': costs, 'projected_s': project(costs),
      'remaining_s': remaining, 'records': self.report['trials'][:2]}
    self.persist()
    require(project(costs) < remaining, 'calibration rejects five-minute budget')
    for block, name in schedule():
      self.trial(name, 'measured', block)
    self.stable()
    summary = {}
    for field in ('wall_s', 'user_cpu_s', 'system_cpu_s', 'max_rss_KiB'):
      values = {n: [self.report['commands'][t['command']][field] for t in self.report['trials']
                    if t['phase'] == 'measured' and t['variant'] == n] for n in ('O2', 'O3')}
      summary[field] = {'variants': {n: {'values': v, 'median': statistics.median(v),
        'min': min(v), 'max': max(v)} for n, v in values.items()},
        'paired_O3_minus_O2': [b - a for a, b in zip(values['O2'], values['O3'])]}
    self.report['summary'] = summary


class Tests(unittest.TestCase):
  def test_listing(self):
    raw = b'.PKGINFO\nusr/lib/modules/kernel\n'
    result = listing(raw)
    self.assertEqual(result, {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw), 'nonempty_paths': 2})
    self.assertNotEqual(listing(raw.replace(b'kernel', b'changed')), result)
    for bad in (b'', b'x', b'x\n\n', b'x\0\n'):
      with self.assertRaises(RuntimeError):
        listing(bad)

  def test_schedule_projection(self):
    jobs = schedule()
    self.assertEqual(len(jobs), 12)
    self.assertEqual(jobs[:2], [(0, 'O3'), (0, 'O2')])
    for block in range(6):
      self.assertEqual({n for b, n in jobs if b == block}, {'O2', 'O3'})
    self.assertEqual(sum(jobs[i][1] == 'O3' for i in range(0, 12, 2)), 3)
    self.assertAlmostEqual(project([2, 3]), 41.4)
    with self.assertRaises(RuntimeError):
      project([2])

  def test_hash_provider(self):
    with tempfile.TemporaryDirectory() as tmp:
      root = Path(tmp)
      own = root / 'libzstd.so.1'
      own.write_bytes(b'full library fixture')
      base.check_hash(own, hashlib.sha256(own.read_bytes()).hexdigest())
      own.write_bytes(b'changed')
      with self.assertRaises(RuntimeError):
        base.check_hash(own, hashlib.sha256(b'full library fixture').hexdigest())
      base.loader_paths(f'libzstd.so.1 => {own} (0x1)\n', root)
      with self.assertRaises(RuntimeError):
        base.loader_paths('libzstd.so.1 => /foreign/libzstd.so.1 (0x1)\n', root)


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  sub = parser.add_subparsers(dest='mode', required=True)
  sub.add_parser('self-test')
  for mode in ('gate', 'bench'):
    p = sub.add_parser(mode)
    for key in ('bundle', 'archive', 'native-gate', 'out'):
      p.add_argument('--' + key, type=Path, required=True)
    p.add_argument('--cpu', type=int, choices=(2,), default=2)
    p.add_argument('--exclusive-pi', action='store_true')
    p.add_argument('--expected-lock-state', choices=('true', 'false'), default='true')
    p.add_argument('--conditions', required=True)
    if mode == 'bench':
      p.add_argument('--gate', type=Path, required=True)
  args = parser.parse_args()
  if args.mode == 'self-test':
    unittest.main(argv=[sys.argv[0]])
  else:
    def interrupted(signum, frame):
      raise KeyboardInterrupt(f'signal {signum}')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    ListingRunner(args).run()


if __name__ == '__main__':
  main()
