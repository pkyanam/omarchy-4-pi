#!/usr/bin/env python3
"""Parent-only isolated full-package qualification and bounded Pi benchmark.

Python >=3.12, standard library only. prepare/self-test never execute package code.
No network, privilege escalation, tuning, package installation or system writes.
"""
import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import subprocess
import sys
import tarfile
import time
import unittest

NAMES = ('stock', 'O2', 'O3')  # All provenance and native correctness checks.
PROTOCOL_VERSION = 3
TIMED_NAMES = ('O2', 'O3')
LEVELS = (1, 3, 9)
CORPORA = ('source.tar', 'stock-libzstd.elf')
ARCHIVES = dict(zip(NAMES, (
  'c3b907c36049b338bda0c6d85260251e48d17e2be6c0e11ddc0dfd4cf9d2e89a',
  'e0a1198fbf1a63d389e064eb093c0d91d9b380d6aa726816ca7fd12a445549ab',
  '2b93983e712c3c5d9dca40d3ac9b43da185e6d5879f6a70b9e509c4f2371d339')))
CLI_HASHES = dict(zip(NAMES, (
  '4eea9767b11369ebfda02824052458efcdcc08e1f82325c952adec3c1cc4db1c',
  '28a39030e681021b19aaacdcfd075fd0afec5f8bc9fc674998013fb48ef31017',
  '959aefe8d92f46a3832f3e0ac3aca22c9eedb077fe98de1bbd8aad9952d79714')))
LIB_HASHES = dict(zip(NAMES, (
  '14d907be630eb1670d14fc104a0982cca01feac5bc75f1846e54f6278c5ee2e2',
  '3e910d386077f19622dd2041f8753bacb6a9f479e93c83920de89c771e10f19a',
  '4fae350fcff23f30d229cf200c37bc78efb6aca8e730019775723753b50e90ea')))
SOURCE_HASH = 'f1cb05ca79a264c240772c789429fc6ecd0d9e5fcd8be5fdeb98338841d65d2c'
LIB = 'usr/lib/libzstd.so.1.5.7'
LOADER = Path('/lib/ld-linux-aarch64.so.1')


def require(ok, why):
  if not ok:
    raise RuntimeError(why)


def sha(path):
  h = hashlib.sha256()
  with Path(path).open('rb') as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
      h.update(chunk)
  return h.hexdigest()


def check_hash(path, expected):
  require(sha(path) == expected, f'hash mismatch: {path}')


def save(path, obj):
  tmp = path.with_suffix('.writing')
  tmp.write_text(json.dumps(obj, indent=2, allow_nan=False) + '\n')
  tmp.replace(path)


def inventory(root):
  result = {}
  for p in sorted(root.rglob('*')):
    key = str(p.relative_to(root))
    if p.is_symlink():
      require(p.resolve().is_relative_to(root.resolve()), f'escaping link: {p}')
      result[key] = {'link': os.readlink(p)}
    elif p.is_file():
      result[key] = {'sha256': sha(p), 'bytes': p.stat().st_size,
                     'mode': p.stat().st_mode & 0o777}
  return result


def prepare(args):
  """Copy pinned archives into distinct directories; safely extract full packages."""
  out = args.out.resolve()
  out.mkdir(mode=0o700)  # exclusive; never overwrite an earlier attempt
  for name in NAMES:
    source = (args.stock if name == 'stock' else
              args.attempt / name / 'zstd-1.5.7-3.1-aarch64.pkg.tar.xz')
    check_hash(source, ARCHIVES[name])
    target = out / name
    target.mkdir()
    archive = target / source.name
    shutil.copyfile(source, archive)
    root = target / 'root'
    root.mkdir()
    with tarfile.open(archive, 'r:xz') as t:
      t.extractall(root, filter='data')
    check_hash(root / 'usr/bin/zstd', CLI_HASHES[name])
    check_hash(root / LIB, LIB_HASHES[name])
  check_hash(args.source, SOURCE_HASH)
  corpus = out / 'corpus'
  corpus.mkdir()
  shutil.copyfile(args.source, corpus / 'source.tar')
  shutil.copyfile(out / 'stock/root' / LIB, corpus / 'stock-libzstd.elf')
  require(sum(p.stat().st_size for p in corpus.iterdir()) <= 32 * 1024**2,
          'corpus exceeds 32 MiB')
  save(out / 'manifest.json', {'schema': 1, 'files': inventory(out),
    'corpus_origin': {'source.tar': 'official zstd v1.5.7 source tar, prior pinned corpus',
                     'stock-libzstd.elf': 'authenticated Arch Linux ARM public stock library'},
    'stock_build_flags': 'unknown', 'pair_variable': 'O2 versus O3 only'})
  print(out)


def check_session_context(context, expected_lock):
  require(context['locked'] == expected_lock and context['outputs'] and context['policies'],
          'expected lock state, outputs and policy required')


def legacy_string(source, name):
  body = re.search(r'const char\* const '+name+r'\s*=\s*(.*?);', source, re.S).group(1)
  parts = re.findall(r'"(?:[^"\\]|\\.)*"', body)
  if name == 'COMPRESSED':
    return b''.join(ast.literal_eval('b'+p) for p in parts)
  return ''.join(ast.literal_eval(p) for p in parts).encode('utf-8')


def balanced_orders():
  # Six paired blocks: three AB and three BA; each position is balanced.
  a, b = TIMED_NAMES
  return [(a, b), (b, a)] * 3


def workload(corpus, level):
  require(corpus in CORPORA and level in LEVELS, 'select one valid corpus and level')
  return {'corpus': corpus, 'level': level}


def measurement_schedule(corpora, levels):
  jobs = [(p, level) for p in sorted(corpora) for level in levels]
  return [(block, p, level, name)
          for block, order in enumerate(balanced_orders())
          for p, level in (jobs if block % 2 == 0 else list(reversed(jobs)))
          for name in order]


def calibration_jobs(corpora, levels):
  return [(p, level, name) for p in sorted(corpora) for level in levels for name in TIMED_NAMES]


def projection(costs, schedule):
  # Only new measured trials remain; calibration is never reused as measurement.
  return max(costs) * len(schedule) * 1.15


def parse_rates(raw, size):
  pattern = r':\s*(\d+)\s*->\s*(\d+)\s*\(x[\d.]+\),\s*([\d.]+) MB/s,\s*([\d.]+) MB/s'
  matches = re.findall(pattern, raw.replace('\r', '\n'))
  require(bool(matches), 'missing complete zstd compression/decode rate pair')
  n, packed, enc, dec = matches[-1]
  values = [float(enc), float(dec)]
  require(int(n) == size and 0 < int(packed) and
          all(math.isfinite(x) and x > 0 for x in values), 'invalid rate/input size')
  return {'compression_MB_s': values[0], 'decode_MB_s': values[1],
          'input_bytes': int(n), 'compressed_bytes': int(packed),
          'scope': 'zstd internal in-memory operation timing; MB=1000000 bytes'}


def loader_paths(raw, own_lib):
  pairs = re.findall(r'^\s*(\S+)\s+=>\s+(/\S+)\s+\(', raw, re.M)
  providers = {soname: Path(path).resolve() for soname, path in pairs}
  require('libzstd.so.1' in providers, 'no dynamic libzstd provider')
  require(providers['libzstd.so.1'] == (own_lib / 'libzstd.so.1').resolve(),
          'foreign libzstd provider')
  require(all(p.is_file() for p in providers.values()), 'missing loader provider')
  return providers


class Runner:
  def __init__(self, args):
    self.args = args
    self.bundle = args.bundle.resolve()
    self.out = args.out.resolve()
    self.out.mkdir(mode=0o700)
    self.tmp = self.out / 'tmp'
    self.tmp.mkdir()
    self.deadline = time.monotonic() + (300 if args.mode == 'bench' else 300)
    self.base = None
    self.report = {'schema': 1, 'measurement_protocol_version': PROTOCOL_VERSION,
      'mode': args.mode, 'status': 'running',
      'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
      'runner_sha256': sha(__file__), 'manifest_sha256': sha(self.bundle / 'manifest.json'),
      'commands': [], 'firmware_actual_clocks': None, 'firmware_throttle_history': None,
      'energy': None, 'unknown_detail': 'firmware clocks/throttle/energy not measured',
      'stock_comparison': 'context only; differing unknown build history',
      'pair_comparison': 'matched full-package O2/O3', 'affinity_cpu': args.cpu,
      'wall_scope': 'child lifecycle, includes loader/startup/I/O; sampled wait overhead <=0.1s',
      'conditions': args.conditions}
    self.env = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': str(self.tmp),
                'TMPDIR': str(self.tmp)}
    # Required to query the existing compositor/session; no loader overrides inherited.
    for key in ('XDG_RUNTIME_DIR', 'HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'OMARCHY_PATH'):
      if key in os.environ:
        self.env[key] = os.environ[key]
    self.shell_command = shutil.which('omarchy-shell')
    require(self.shell_command is not None, 'omarchy-shell unavailable')

  def persist(self):
    save(self.out / 'results.json', self.report)

  def health(self):
    temperatures = {str(p): int(p.read_text()) for p in
                    Path('/sys/class/thermal').glob('thermal_zone*/temp')}
    alarms = {str(p): p.read_text().strip() for p in
              Path('/sys/class/hwmon').glob('*/in0_lcrit_alarm')}
    state = {'monotonic_s': time.monotonic(), 'temperatures_mC': temperatures,
      'native_voltage_alarms': alarms,
      'requested_frequency_kHz': {str(p): p.read_text().strip() for p in
        Path('/sys/devices/system/cpu/cpufreq').glob('policy*/scaling_cur_freq')},
      'pressure': {k: Path('/proc/pressure', k).read_text() for k in ('cpu', 'memory', 'io')},
      'loadavg': Path('/proc/loadavg').read_text(),
      'meminfo': Path('/proc/meminfo').read_text()}
    # Persist the offending sample before stopping, including missing sensors.
    with (self.out / 'health.jsonl').open('a') as f:
      f.write(json.dumps(state) + '\n')
    require(temperatures and max(temperatures.values()) < 70000, 'thermal stop >=70C or unavailable')
    require(alarms and all(x == '0' for x in alarms.values()), 'native voltage alarm nonzero/unavailable')
    require(time.monotonic() < self.deadline, 'overall deadline')
    return state

  def call(self, argv, *, data=None, expected=0, monitor=True):
    argv = list(map(str, argv))
    idx = len(self.report['commands'])
    stem = self.out / f'{idx:04d}'
    item = {'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'argv': argv, 'environment': self.env, 'expected_exit': expected,
            'stdout': stem.name + '.stdout', 'stderr': stem.name + '.stderr'}
    self.report['commands'].append(item)
    if data is not None:
      (stem.with_suffix('.stdin')).write_bytes(data)
      item['stdin'] = stem.name + '.stdin'
    self.persist()
    start = time.monotonic()
    def limits():
      os.sched_setaffinity(0, {self.args.cpu})
      resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2,) * 2)
      resource.setrlimit(resource.RLIMIT_FSIZE, (64 * 1024**2,) * 2)
      resource.setrlimit(resource.RLIMIT_CPU, (20, 21))
    with stem.with_suffix('.stdout').open('wb') as stdout, stem.with_suffix('.stderr').open('wb') as stderr:
      stdin = stem.with_suffix('.stdin').open('rb') if data is not None else open(os.devnull, 'rb')
      with stdin:
        p = subprocess.Popen(argv, stdin=stdin, stdout=stdout, stderr=stderr,
          cwd=self.tmp, env=self.env, start_new_session=True, preexec_fn=limits)
        try:
          while True:
            pid, status, usage = os.wait4(p.pid, os.WNOHANG)
            if pid:
              p.returncode = os.waitstatus_to_exitcode(status)
              item.update(exit_code=p.returncode, wall_s=time.monotonic()-start,
                user_cpu_s=usage.ru_utime, system_cpu_s=usage.ru_stime,
                max_rss_KiB=usage.ru_maxrss, voluntary_context_switches=usage.ru_nvcsw,
                involuntary_context_switches=usage.ru_nivcsw)
              break
            if monitor:
              self.health()
            require(time.monotonic() < min(self.deadline, start + 25), 'child deadline')
            time.sleep(.05 if monitor else .01)
        except BaseException as exc:
          try:
            os.killpg(p.pid, signal.SIGKILL)
          except ProcessLookupError:
            pass  # Child exited between wait4(WNOHANG) and the stop signal.
          _, status, usage = os.wait4(p.pid, 0)
          p.returncode = os.waitstatus_to_exitcode(status)
          item.update(stop=str(exc), exit_code=p.returncode, wall_s=time.monotonic()-start,
            user_cpu_s=usage.ru_utime, system_cpu_s=usage.ru_stime, max_rss_KiB=usage.ru_maxrss)
          raise
        finally:
          self.persist()
    require((p.returncode == 0) if expected == 0 else (p.returncode > 0), f'command exit mismatch: {idx}')
    return stem.with_suffix('.stdout').read_bytes()

  def context(self):
    policies = {}
    for p in Path('/sys/devices/system/cpu/cpufreq').glob('policy*'):
      policies[str(p)] = {k: (p / k).read_text().strip() for k in
        ('scaling_governor', 'scaling_min_freq', 'scaling_max_freq', 'scaling_driver')}
    return {'policies': policies, 'kernel': os.uname().release,
      'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
      'online_cpus': Path('/sys/devices/system/cpu/online').read_text().strip(),
      'locked': self.call([self.shell_command, 'lock', 'isLocked'], monitor=False).decode().strip(),
      'outputs': [{k: m[k] for k in ('name', 'width', 'height', 'refreshRate', 'scale', 'dpmsStatus')}
        for m in json.loads(self.call(['/usr/bin/hyprctl', 'monitors', '-j'], monitor=False))],
      'packages': self.call(['/usr/bin/pacman', '-Q', 'zstd', 'glibc', 'zlib', 'xz', 'lz4'], monitor=False).decode()}

  def stable(self):
    self.health()
    observed = self.context()
    if observed != self.base:
      self.report['drift_context'] = observed
      self.persist()
    require(observed == self.base, 'policy/session/package drift: reject whole run')
    fingerprints = {v['path']: v['sha256'] for group in self.report['providers'].values()
                    for v in group.values()}
    fingerprints[self.report['loader']['path']] = self.report['loader']['sha256']
    for path, expected in fingerprints.items():
      check_hash(path, expected)

  def command(self, name, args, binary='zstd'):
    root = self.bundle / name / 'root'
    return [LOADER, '--library-path', root / 'usr/lib', root / 'usr/bin' / binary, *args]

  def z(self, name, args, data=None, expected=0, binary='zstd'):
    return self.call(self.command(name, args, binary), data=data, expected=expected)

  def verify(self):
    require(sys.platform == 'linux' and os.geteuid() != 0, 'normal Linux user required')
    require(self.args.exclusive_pi, 'parent must hold exclusive Pi lease')
    require(self.args.cpu in os.sched_getaffinity(0), 'CPU unavailable')
    model = Path('/sys/firmware/devicetree/base/model').read_bytes().rstrip(b'\0').decode()
    rev = Path('/sys/firmware/devicetree/base/system/linux,revision').read_bytes()
    require('Raspberry Pi 4 Model B' in model and int.from_bytes(rev, 'big') == 0xc03115,
            'wrong native 4GB board cohort')
    self.report.update(board_model=model, revision=rev.hex())
    manifest = json.loads((self.bundle / 'manifest.json').read_text())
    actual = inventory(self.bundle)
    actual.pop('manifest.json', None)
    require(actual == manifest['files'], 'bundle inventory mismatch')
    check_hash(self.bundle / 'corpus/source.tar', SOURCE_HASH)
    check_hash(self.bundle / 'corpus/stock-libzstd.elf', LIB_HASHES['stock'])
    require(sum(p.stat().st_size for p in (self.bundle/'corpus').iterdir()) <= 32*1024**2,
            'corpus size limit')
    check_hash('/usr/bin/zstd', CLI_HASHES['stock'])
    check_hash('/usr/lib/libzstd.so.1', LIB_HASHES['stock'])
    providers = {}
    for name in NAMES:
      root = self.bundle / name / 'root'
      archive = list((self.bundle/name).glob('*.pkg.tar.xz'))
      require(len(archive) == 1, 'archive collision')
      check_hash(archive[0], ARCHIVES[name])
      check_hash(root / 'usr/bin/zstd', CLI_HASHES[name])
      check_hash(root / LIB, LIB_HASHES[name])
      for binary in ('zstd', 'pzstd'):
        elf = root / 'usr/bin' / binary
        header = self.call(['/usr/bin/readelf', '-h', elf]).decode()
        require('AArch64' in header and 'DYN' in header, 'wrong ELF ABI')
        # Preserve requirements, including GLIBC_ABI_DT_RELR, and actual loader --verify.
        self.call(['/usr/bin/readelf', '-V', elf])
        self.call(['/usr/bin/readelf', '-V', root / LIB])
        self.call([LOADER, '--verify', elf])
        trace = self.call([LOADER, '--library-path', root / 'usr/lib', '--list', elf]).decode()
        paths = loader_paths(trace, root / 'usr/lib')
        providers[name + '/' + binary] = {k: {'path': str(p), 'sha256': sha(p)} for k,p in paths.items()}
      self.z(name, ['--version'])  # forces symbol-version resolution on target
    self.report['providers'] = providers
    self.report['loader'] = {'path': str(LOADER.resolve()), 'sha256': sha(LOADER)}
    self.base = self.context()
    check_session_context(self.base, self.args.expected_lock_state)
    self.report['context'] = self.base
    self.persist()

  def gate(self):
    with tarfile.open(self.bundle / 'corpus/source.tar') as t:
      golden = {m.name: t.extractfile(m).read() for m in t.getmembers()
                if m.isfile() and '/golden-decompression-errors/' in m.name}
      sources = {m.name: t.extractfile(m).read() for m in t.getmembers()
                 if m.isfile() and m.name.startswith('zstd-1.5.7/tests/') and m.name.endswith('.c')}
    data = sources['zstd-1.5.7/tests/fuzzer.c']
    samples = self.tmp / 'samples'
    samples.mkdir()
    for i, content in enumerate(sources.values()):
      (samples / f'{i}.c').write_bytes(content)
    legacy_source = sources['zstd-1.5.7/tests/legacy.c'].decode()
    legacy = legacy_string(legacy_source, 'COMPRESSED')
    expected = legacy_string(legacy_source, 'EXPECTED')
    starts = [i for i in range(len(legacy)-3) if legacy[i+1:i+4] == bytes.fromhex('b52ffd')]
    require([legacy[i] for i in starts] == [0x24,0x25,0x26,0x27,0x28], 'legacy fixture shape')
    for name in NAMES:
      self.stable()
      for fmt in ('zstd', 'gzip', 'xz', 'lzma', 'lz4'):
        encoded = self.z(name, ['-q', '--single-thread', '--format='+fmt, '-c'], data)
        for decoder in NAMES:
          require(self.z(decoder, ['-q', '-dc'], encoded) == data, 'cross-decode mismatch')
      for level in (1, 3, 9):
        encoded = self.z(name, ['-q', '--single-thread', f'-{level}', '-c'], data)
        for decoder in NAMES:
          require(self.z(decoder, ['-q', '-dc'], encoded) == data, 'level cross-decode mismatch')
      encoded = self.z(name, ['-q', '-T2', '-c'], data)
      for binary in ('unzstd', 'zstdcat', 'zstdmt'):
        require(self.z(name, ['-q', '-dc'], encoded, binary=binary) == data, 'wrapper mismatch')
      packed = self.z(name, ['-q', '-p', '1', '-c'], data, binary='pzstd')
      require(self.z(name, ['-q', '-p', '1', '-dc'], packed, binary='pzstd') == data, 'pzstd mismatch')
      dictionary = self.tmp / (name + '.dict')
      self.z(name, ['--train', '-q', *sorted(samples.iterdir()), '-o', dictionary, '--maxdict=8192'])
      packed = self.z(name, ['-q', '-D', dictionary, '-c'], data)
      require(self.z(name, ['-q', '-D', dictionary, '-dc'], packed) == data, 'dictionary mismatch')
      self.z(name, ['-q', '-dc'], b'not a zstd frame', expected=1)
      self.z(name, ['-q', '-dc'], packed[:-7], expected=1)
      require(bool(golden), 'golden error fixtures missing')
      for broken in golden.values():
        self.z(name, ['-q', '-t'], broken, expected=1)
      for i, start in enumerate(starts):
        frame = legacy[start:starts[i+1] if i+1 < len(starts) else len(legacy)]
        decoded = self.z(name, ['-q', '-dc'], frame, expected=1 if i == 0 else 0)
        if i:
          require(decoded == expected[:len(expected)//5], 'legacy mismatch')
      require(self.z(name, ['-q', '-dc'], legacy[starts[1]:]) == expected[len(expected)//5:],
              'legacy concatenation mismatch')
    self.stable()

  def bench(self):
    gate = json.loads(self.args.gate.read_text())
    for key in ('runner_sha256', 'manifest_sha256', 'context', 'providers', 'loader'):
      require(gate[key] == self.report[key], f'gate changed: {key}')
    require(gate['mode'] == 'gate' and gate['status'] == 'complete', 'native gate incomplete')
    self.report['gate_sha256'] = sha(self.args.gate)
    unit = workload(self.args.corpus, self.args.level)
    corpora = [self.bundle / 'corpus' / unit['corpus']]
    levels = (unit['level'],)
    schedule = measurement_schedule(corpora, levels)
    calibrations = calibration_jobs(corpora, levels)
    self.report['measurement_protocol'] = {
      'version': PROTOCOL_VERSION, 'timed_variants': TIMED_NAMES,
      'provenance_and_correctness_variants': NAMES,
      'stock_role': 'context-only provenance and native correctness; no timing',
      'workload_unit': unit, 'corpora': [p.name for p in corpora], 'levels': levels,
      'full_matrix_units': [workload(p, l) for p in CORPORA for l in LEVELS],
      'claim_scope': 'one workload unit; all six complete units required for full matrix; never pool',
      'blocks': len(balanced_orders()), 'balanced_orders': balanced_orders(),
      'measured_trial_count': len(schedule), 'calibration_trial_count': len(calibrations),
      'cli': '--single-thread -bLEVEL -i1', 'deadline_s': 300,
      'projection_headroom_fraction': 0.15,
      'schedule': [dict(block=b, corpus=p.name, level=l, variant=n) for b,p,l,n in schedule]}
    self.persist()
    trials = []
    self.report['trials'] = trials
    def trial(name, corpus, level, phase, block):
      start = time.monotonic()
      self.stable()
      # Fixed cool-start gate, no forced governor/fan/cache changes.
      while max(self.health()['temperatures_mC'].values()) > 52000:
        time.sleep(.5)
      self.stable()
      raw = self.z(name, ['--single-thread', f'-b{level}', '-i1', corpus])
      idx = len(self.report['commands']) - 1
      # CLI writes bench progress to stderr on some builds.
      raw += (self.out / self.report['commands'][idx]['stderr']).read_bytes()
      rates = parse_rates(raw.decode(errors='replace'), corpus.stat().st_size)
      trials.append(dict(variant=name, corpus=corpus.name, level=level, phase=phase,
                         block=block, command=idx, **rates))
      self.persist()
      self.stable()
      return time.monotonic() - start
    # Fresh bounded calibration: both pair variants on this exact corpus and level.
    costs = [trial(n, p, level, 'calibration', -1) for p,level,n in calibrations]
    projected = projection(costs, schedule)
    self.report['calibration'] = {'measured_trial_seconds': costs,
      'records': [dict(corpus=p.name, level=l, variant=n, lifecycle_s=cost,
                       trial_index=i, command=trials[i]['command'])
                  for i, ((p,l,n), cost) in enumerate(zip(calibrations, costs))],
      'projected_new_measured_trials': len(schedule), 'headroom_fraction': 0.15,
      'conservative_remaining_seconds': projected, 'remaining_budget_s': self.deadline-time.monotonic(),
      'workload_unit': unit,
      'caveat': 'same-workload cost is a projection; cooling and scheduler delays can exhaust deadline'}
    self.persist()
    require(projected < self.deadline-time.monotonic(), 'calibration rejects five-minute budget; retain, redesign explicitly')
    for block, corpus, level, name in schedule:
      trial(name, corpus, level, 'measured', block)
    self.stable()

  def run(self):
    try:
      self.verify()
      self.gate() if self.args.mode == 'gate' else self.bench()
      self.report['status'] = 'complete'
    except BaseException as exc:
      self.report.update(status='rejected', reason=f'{type(exc).__name__}: {exc}')
      raise
    finally:
      self.report['ended_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
      self.persist()


class Tests(unittest.TestCase):
  def test_session_context(self):
    for state in ('true', 'false'):
      context = {'locked': state, 'outputs': [{}], 'policies': {'cpu': {}}}
      check_session_context(context, state)
      with self.assertRaises(RuntimeError):
        check_session_context(context, 'false' if state == 'true' else 'true')
      context['outputs'] = []
      with self.assertRaises(RuntimeError):
        check_session_context(context, state)

  def test_legacy_utf8(self):
    source = 'const char* const EXPECTED = "it’s a door." " More.";'
    self.assertEqual(legacy_string(source, 'EXPECTED'), 'it’s a door. More.'.encode())
    source = r'const char* const COMPRESSED = "\x25\xb5\x2f\xfd";'
    self.assertEqual(legacy_string(source, 'COMPRESSED'), bytes.fromhex('25b52ffd'))

  def test_rate_parser(self):
    raw = ': 8919040 -> 2264833 (x3.938), 49.0 MB/s\r: 8919040 -> 2264833 (x3.938), 49.0 MB/s, 392.2 MB/s\r 3#'
    self.assertEqual(parse_rates(raw, 8919040)['decode_MB_s'], 392.2)
    for bad, size in [(raw, 1), (raw.replace('392.2', '0.0'), 8919040), ('49 MB/s', 1)]:
      with self.assertRaises(RuntimeError):
        parse_rates(bad, size)

  def test_order(self):
    for corpus in CORPORA:
      for level in LEVELS:
        p = Path(corpus)
        schedule = measurement_schedule([p], [level])
        self.assertEqual(len(schedule), 12)
        orders = []
        for block in range(6):
          pair = [(c,l,n) for b,c,l,n in schedule if b == block]
          self.assertEqual([(c,l) for c,l,n in pair], [(p,level)] * 2)
          orders.append(tuple(n for c,l,n in pair))
        self.assertEqual(orders, [('O2', 'O3'), ('O3', 'O2')] * 3)

  def test_projection(self):
    for corpus in CORPORA:
      for level in LEVELS:
        p = Path(corpus)
        self.assertEqual(calibration_jobs([p], [level]), [(p,level,'O2'), (p,level,'O3')])
        self.assertAlmostEqual(projection([1, 4], measurement_schedule([p], [level])), 4 * 12 * 1.15)

  def test_bench_protocol(self):
    # Exercise actual dispatch, selection and persisted evidence for all six units.
    import tempfile
    from types import SimpleNamespace
    for corpus in CORPORA:
      for level in LEVELS:
        with self.subTest(corpus=corpus, level=level), tempfile.TemporaryDirectory() as d:
          runner = Runner.__new__(Runner)
          runner.bundle = runner.out = Path(d)
          (runner.bundle / 'corpus').mkdir()
          for i, name in enumerate(CORPORA, 1):
            (runner.bundle / 'corpus' / name).write_bytes(b'x' * i)
          runner.args = SimpleNamespace(mode='bench', gate=Path(d) / 'gate.json', corpus=corpus, level=level)
          runner.report = {k: {} for k in ('runner_sha256', 'manifest_sha256', 'context', 'providers', 'loader')}
          save(runner.args.gate, dict(runner.report, mode='gate', status='complete'))
          runner.report['commands'] = []
          runner.deadline = time.monotonic() + 300
          runner.stable = lambda: None
          runner.health = lambda: {'temperatures_mC': {'test': 50000}}
          calls = []
          def fake_z(name, args):
            calls.append((name, args))
            self.assertIn(name, ('O2', 'O3'))
            self.assertEqual(args, ['--single-thread', f'-b{level}', '-i1', runner.bundle/'corpus'/corpus])
            stderr = f"{len(runner.report['commands'])}.stderr"
            (runner.out / stderr).write_bytes(b'')
            runner.report['commands'].append({'stderr': stderr})
            return f': {args[-1].stat().st_size} -> 1 (x1.0), 1.0 MB/s, 1.0 MB/s'.encode()
          runner.z = fake_z
          runner.bench()
          trials = runner.report['trials']
          self.assertEqual(len(calls), 14)
          self.assertEqual([(t['variant'],t['phase']) for t in trials[:2]],
                           [('O2','calibration'), ('O3','calibration')])
          self.assertTrue(all(t['phase'] == 'measured' for t in trials[2:]))
          self.assertTrue(all((t['corpus'],t['level']) == (corpus,level) for t in trials))
          expected = [(b,corpus,level,n) for b in range(6) for n in
                      (('O2','O3') if b % 2 == 0 else ('O3','O2'))]
          self.assertEqual([(t['block'],t['corpus'],t['level'],t['variant']) for t in trials[2:]], expected)
          saved = json.loads((runner.out/'results.json').read_text())
          protocol = saved['measurement_protocol']
          self.assertEqual(protocol['version'], 3)
          self.assertEqual(protocol['workload_unit'], {'corpus':corpus, 'level':level})
          self.assertEqual(protocol['corpora'], [corpus])
          self.assertEqual(protocol['levels'], [level])
          self.assertEqual(protocol['measured_trial_count'], 12)
          self.assertEqual(protocol['calibration_trial_count'], 2)
          self.assertEqual(protocol['schedule'], [dict(block=b,corpus=p,level=l,variant=n) for b,p,l,n in expected])
          self.assertEqual(protocol['full_matrix_units'], [dict(corpus=p,level=l) for p in CORPORA for l in LEVELS])
          calibration = saved['calibration']
          self.assertEqual(calibration['projected_new_measured_trials'], 12)
          self.assertEqual(len(calibration['records']), 2)
          self.assertTrue(all((r['corpus'],r['level']) == (corpus,level) for r in calibration['records']))
          self.assertAlmostEqual(calibration['conservative_remaining_seconds'],
                                 max(calibration['measured_trial_seconds']) * 12 * 1.15)
          # A new invocation must reject projection before dispatching measured work,
          # preserving the two fresh calibration records via the normal run boundary.
          runner.deadline = time.monotonic() + 300
          runner.verify = lambda: None
          runner.report['commands'] = []
          calls.clear()
          from unittest.mock import patch
          with patch(__name__ + '.projection', return_value=301):
            with self.assertRaisesRegex(RuntimeError, 'calibration rejects'):
              runner.run()
          rejected = json.loads((runner.out/'results.json').read_text())
          self.assertEqual(rejected['status'], 'rejected')
          self.assertEqual(len(calls), 2)
          self.assertEqual(len(rejected['trials']), 2)
          self.assertEqual(rejected['calibration']['conservative_remaining_seconds'], 301)

  def test_invalid_workload(self):
    # Test the public parser without ever reaching target preflight.
    from unittest.mock import patch
    import contextlib
    import io
    base = ['runner', 'bench', '--bundle', '/unused', '--out', '/unused',
            '--gate', '/unused', '--conditions', 'host test']
    for selection in ([], ['--corpus','source.tar'], ['--level','1'],
                      ['--corpus','other','--level','1'],
                      ['--corpus','source.tar','--level','2']):
      with patch.object(sys, 'argv', base + selection), contextlib.redirect_stderr(io.StringIO()):
        with self.assertRaises(SystemExit) as error:
          main()
        self.assertEqual(error.exception.code, 2)
    for corpus,level in [('other',1), ('source.tar',2), (None,None)]:
      with self.assertRaises(RuntimeError):
        workload(corpus, level)

  def test_hash_and_loader(self):
    import tempfile
    with tempfile.TemporaryDirectory() as d:
      root = Path(d)
      own, foreign = root/'own', root/'foreign'
      own.mkdir(); foreign.mkdir()
      for p in (own, foreign):
        (p/'libzstd.so.1').write_bytes(b'library')
      check_hash(own/'libzstd.so.1', hashlib.sha256(b'library').hexdigest())
      with self.assertRaises(RuntimeError):
        check_hash(own/'libzstd.so.1', '0'*64)
      trace = f' libzstd.so.1 => {own}/libzstd.so.1 (0x123)\n'
      self.assertEqual(loader_paths(trace, own)['libzstd.so.1'], (own/'libzstd.so.1').resolve())
      with self.assertRaises(RuntimeError):
        loader_paths(trace.replace(str(own), str(foreign)), own)
      with self.assertRaises(RuntimeError):
        loader_paths('libzstd.so.1 => not found', own)


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  sub = parser.add_subparsers(dest='mode', required=True)
  sub.add_parser('self-test')
  p = sub.add_parser('prepare', help='host-only copy/extract pinned archives; no package execution')
  p.add_argument('--attempt', type=Path, required=True)
  p.add_argument('--stock', type=Path, required=True)
  p.add_argument('--source', type=Path, required=True)
  p.add_argument('--out', type=Path, required=True)
  for mode in ('gate', 'bench'):
    p = sub.add_parser(mode, help='parent ONLY on exclusive native Pi; five-minute hard budget')
    p.add_argument('--bundle', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--cpu', type=int, default=2)
    p.add_argument('--exclusive-pi', action='store_true')
    p.add_argument('--conditions', required=True)
    p.add_argument('--expected-lock-state', choices=('true', 'false'), default='true')
    if mode == 'bench':
      p.add_argument('--gate', type=Path, required=True)
      p.add_argument('--corpus', choices=CORPORA, required=True)
      p.add_argument('--level', type=int, choices=LEVELS, required=True)
  args = parser.parse_args()
  if args.mode == 'self-test':
    unittest.main(argv=[sys.argv[0]])
  elif args.mode == 'prepare':
    require(sys.version_info >= (3,12), 'Python >=3.12 required for safe tar extraction')
    prepare(args)
  else:
    def interrupted(signum, frame):
      raise KeyboardInterrupt(f'signal {signum}')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    Runner(args).run()


if __name__ == '__main__':
  main()
