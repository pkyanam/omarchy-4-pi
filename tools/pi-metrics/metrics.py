"""Pi measurement protocol v2. Python 3 standard library; see README.md."""
import argparse
import base64
import datetime
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import uuid

VERSION = '2.0.0'
HERE = Path(__file__).resolve().parent


def result(value, unit, source, status='ok', detail=''):
  return dict(value=value, unit=unit, source=source, status=status, detail=detail)


def unknown(unit, source, detail, status='unavailable'):
  return result(None, unit, source, status, detail)


def read(path):
  return Path(path).read_text().strip()


def file_probe(path, unit='text', convert=str):
  try:
    return result(convert(read(path)), unit, str(path))
  except PermissionError:
    return unknown(unit, str(path), 'permission denied', 'permission_denied')
  except OSError:
    return unknown(unit, str(path), 'file unavailable')
  except (ValueError, IndexError):
    return unknown(unit, str(path), 'invalid content', 'invalid')


def run(argv, timeout=15):
  return subprocess.run(argv, text=True, capture_output=True, timeout=timeout, check=True,
                        env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C'})


def command_probe(argv, unit='text', convert=lambda s: s.strip(), timeout=15):
  source = shlex.join(argv)
  try:
    return result(convert(run(argv, timeout).stdout), unit, source)
  except FileNotFoundError:
    return unknown(unit, source, 'command unavailable')
  except subprocess.TimeoutExpired:
    return unknown(unit, source, 'timeout', 'error')
  except subprocess.CalledProcessError as exc:
    return unknown(unit, source, f'exit {exc.returncode}', 'error')
  except (ValueError, IndexError):
    return unknown(unit, source, 'invalid output', 'invalid')


def revision(data):
  if len(data) != 4:
    raise ValueError('revision must be one big-endian DT cell')
  code = int.from_bytes(data, 'big')
  # Old-style revisions carry no new-style RAM field.
  ram_code = (code >> 20) & 7
  ram = (256 * 2 ** ram_code) if code & (1 << 23) and ram_code <= 6 else None
  return f'{code:08x}', ram


def throttle(text):
  match = re.fullmatch(r'throttled=(0x[0-9a-fA-F]+)\s*', text)
  if not match:
    raise ValueError('invalid throttle response')
  return int(match[1], 16)


def openssl_rate(text):
  rows = [line.split(':') for line in text.splitlines() if line.startswith('+F:')]
  if len(rows) != 1 or len(rows[0]) != 4:
    raise ValueError('expected one fixed-buffer machine-readable rate')
  rate = float(rows[0][3]) / (1024 * 1024)
  if not math.isfinite(rate) or rate <= 0:
    raise ValueError('invalid rate')
  return rate


def kernel_config(root, release):
  root = Path(root)
  live = root / 'proc/config.gz'
  try:
    return gzip.decompress(live.read_bytes()).decode(), '/proc/config.gz (running kernel)'
  except FileNotFoundError:
    pass
  # No glob: another installed kernel's config must never establish posture.
  build = root / 'usr/lib/modules' / release / 'build'
  if read(build / 'include/config/kernel.release') != release:
    raise ValueError('build config release mismatch')
  return read(build / '.config'), f'/usr/lib/modules/{release}/build/.config (kernel.release matched)'


def config_values(text):
  values = {}
  for line in text.splitlines():
    if line.startswith('CONFIG_') and '=' in line:
      key, value = line.split('=', 1)
      values[key] = value
    elif re.fullmatch(r'# CONFIG_\w+ is not set', line):
      values[line.split()[1]] = 'n'
  return values


def telemetry():
  probes = {}
  for policy in sorted(Path('/sys/devices/system/cpu/cpufreq').glob('policy*')):
    for name in ('scaling_cur_freq', 'cpuinfo_cur_freq', 'cpuinfo_max_freq', 'scaling_max_freq', 'scaling_driver', 'scaling_governor'):
      numeric = name.endswith('freq')
      probes[f'{policy.name}.{name}'] = file_probe(policy / name, 'kHz' if numeric else 'text', int if numeric else str)
  for zone in sorted(Path('/sys/class/thermal').glob('thermal_zone*')):
    probes[f'{zone.name}.type'] = file_probe(zone / 'type')
    probes[f'{zone.name}.temp'] = file_probe(zone / 'temp', 'milliCelsius', int)
  raw = command_probe(['vcgencmd', 'get_throttled'], 'bitmask', throttle)
  probes['firmware.throttled_raw'] = raw
  for bit, name in {0: 'undervoltage_now', 1: 'frequency_capped_now', 2: 'throttled_now', 3: 'soft_temp_limit_now', 16: 'undervoltage_since_boot', 17: 'frequency_capped_since_boot', 18: 'throttled_since_boot', 19: 'soft_temp_limit_since_boot'}.items():
    probes['firmware.' + name] = (result(bool(raw['value'] & (1 << bit)), 'boolean', raw['source']) if raw['status'] == 'ok' else unknown('boolean', raw['source'], raw['detail'], raw['status']))
  probes['firmware.arm_clock'] = command_probe(['vcgencmd', 'measure_clock', 'arm'], 'Hz', lambda s: int(re.fullmatch(r'frequency\(\d+\)=(\d+)\s*', s)[1]) if re.fullmatch(r'frequency\(\d+\)=(\d+)\s*', s) else int('invalid'))
  probes['uptime'] = file_probe('/proc/uptime', 'seconds', lambda s: float(s.split()[0]))
  probes['loadavg'] = file_probe('/proc/loadavg')
  for kind in ('cpu', 'memory', 'io'):
    probes['pressure.' + kind] = file_probe('/proc/pressure/' + kind)
  return probes


def collect(metadata, bench=False):
  if sys.platform != 'linux' or os.geteuid() != 0:
    raise ValueError('probe requires Linux and effective uid 0; no implicit escalation')
  start = datetime.datetime.now(datetime.timezone.utc).isoformat()
  release = os.uname().release
  probes = {'kernel.release': result(release, 'text', 'uname -r'),
            'collector.euid': result(os.geteuid(), 'uid', 'geteuid')}
  path = '/proc/device-tree/system/linux,revision'
  try:
    code, ram = revision(Path(path).read_bytes())
    probes['board.revision'] = result(code, 'hex', path)
    probes['board.nominal_ram'] = result(ram, 'MiB', path) if ram else unknown('MiB', path, 'old-style revision; RAM unknown')
  except (OSError, ValueError) as exc:
    probes['board.revision'] = unknown('hex', path, type(exc).__name__)
    probes['board.nominal_ram'] = unknown('MiB', path, 'revision unavailable')
  probes['board.model'] = file_probe('/proc/device-tree/model', convert=lambda s: s.rstrip('\0'))
  probes['cpu.implementer_part_features'] = file_probe('/proc/cpuinfo', convert=lambda s: '\n'.join(line for line in s.splitlines() if line.startswith(('CPU implementer', 'CPU part', 'Features'))))
  for name, path, unit in [('memory.meminfo', '/proc/meminfo', 'KiB fields except HugePages counters'), ('memory.swappiness', '/proc/sys/vm/swappiness', 'relative IO cost (0-200)'), ('memory.thp', '/sys/kernel/mm/transparent_hugepage/enabled', 'text'), ('zram.compressor', '/sys/block/zram0/comp_algorithm', 'text'), ('zram.size', '/sys/block/zram0/disksize', 'bytes'), ('zram.mm_stat', '/sys/block/zram0/mm_stat', 'kernel mm_stat fields'), ('crypto.registered', '/proc/crypto', 'text'), ('security.meltdown', '/sys/devices/system/cpu/vulnerabilities/meltdown', 'text')]:
    probes[name] = file_probe(path, unit, int if name in ('memory.swappiness', 'zram.size') else str)
  probes['security.kpti_runtime'] = unknown('boolean', 'none', 'not inferred from cmdline, KASLR, or Meltdown status', 'not_measured')
  probes['security.kpti_request'] = file_probe('/proc/cmdline', convert=lambda s: ' '.join(x for x in s.split() if x.startswith(('kpti=', 'mitigations='))) or 'unspecified')
  try:
    config, source = kernel_config('/', release)
    flags = config_values(config)
    probes['kernel.config_sha256'] = result(hashlib.sha256(config.encode()).hexdigest(), 'sha256', source)
    for key in ('CONFIG_HZ', 'CONFIG_LTO_NONE', 'CONFIG_LTO_CLANG', 'CONFIG_LTO_CLANG_THIN', 'CONFIG_UNMAP_KERNEL_AT_EL0'):
      probes['kernel.' + key] = result(flags[key], 'config value', source) if key in flags else unknown('config value', source, 'symbol absent')
  except (OSError, ValueError, UnicodeError):
    for key in ('config_sha256', 'CONFIG_HZ', 'CONFIG_LTO_NONE', 'CONFIG_LTO_CLANG', 'CONFIG_LTO_CLANG_THIN', 'CONFIG_UNMAP_KERNEL_AT_EL0'):
      probes['kernel.' + key] = unknown('config value', 'running kernel config', 'matching readable config unavailable')
  probes['packages.versions'] = command_probe(['pacman', '-Q'], convert=lambda s: '\n'.join(line for line in s.splitlines() if line.split()[0].startswith(('linux', 'omarchy', 'openssl', 'python', 'raspberrypi', 'firmware'))) or 'no matching packages')
  probes['build.installed_compiler_flags'] = unknown('text', 'none', 'local makepkg settings are not installed artifact provenance', 'not_measured')
  probes['media.video_nodes'] = result(len(list(Path('/dev').glob('video[0-9]*'))), 'count', '/dev/video[0-9]*', detail='node count does not establish decode support')
  probes['pcie.links'] = command_probe(['lspci', '-D', '-vv'], convert=lambda s: '\n'.join(line for line in s.splitlines() if (line and not line[0].isspace()) or 'LnkCap:' in line or 'LnkSta:' in line))
  probes['energy'] = unknown('joules', 'none', 'external instrumentation required', 'not_measured')
  before = telemetry()
  for key in ('python.getpid', 'python.open_close', 'python.null_loop', 'openssl.aes256cbc', 'openssl.sha256'):
    probes[key] = unknown('us/iteration' if key.startswith('python') else 'MiB/s', 'disabled', 'enable --bench explicitly', 'not_measured')
  if bench:
    probes['runtime.python'] = result(sys.version, 'text', 'sys.version')
    probes['runtime.openssl'] = command_probe(['openssl', 'version'])
    def timed(fn, n):
      t = time.perf_counter_ns()
      for _ in range(n):
        fn()
      return (time.perf_counter_ns() - t) / n / 1000
    # Python call/loop overhead deliberately included; not bare syscall latency.
    probes['python.getpid'] = result(timed(os.getpid, 200000), 'us/iteration', 'Python os.getpid; 200000 iterations')
    probes['python.open_close'] = result(timed(lambda: os.close(os.open('/dev/null', os.O_RDONLY)), 20000), 'us/iteration', 'Python open+close /dev/null; 20000 iterations')
    probes['python.null_loop'] = result(timed(lambda: None, 200000), 'us/iteration', 'Python empty callable; 200000 iterations')
    for algo, key in [('aes-256-cbc', 'aes256cbc'), ('sha256', 'sha256')]:
      argv = ['openssl', 'speed', '-mr', '-elapsed', '-seconds', '1', '-bytes', '8192', '-evp', algo]
      # OpenSSL machine-readable records are written to stderr on some versions.
      try:
        proc = run(argv)
        probes['openssl.' + key] = result(openssl_rate(proc.stdout + '\n' + proc.stderr), 'MiB/s', shlex.join(argv), detail='8192 bytes; elapsed wall time; CBC is not dm-crypt XTS throughput')
      except (OSError, subprocess.SubprocessError, ValueError):
        probes['openssl.' + key] = unknown('MiB/s', shlex.join(argv), 'missing, failed, or invalid OpenSSL output', 'error')
  return dict(schema_version=2, tool_version=VERSION, sample_id=str(uuid.uuid4()), started_utc=start,
              ended_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), metadata=metadata,
              probes=probes, before=before, after=telemetry())


def validate(value, schema, root=None):
  """Strict validation of the subset used by schema-v2.json; no dependencies."""
  if root is None:
    root = schema
  if '$ref' in schema:
    validate(value, root['$defs'][schema['$ref'].removeprefix('#/$defs/')], root)
    return
  for part in schema.get('allOf', []):
    validate(value, part, root)
  if 'anyOf' in schema:
    for option in schema['anyOf']:
      try:
        validate(value, option, root)
        return
      except ValueError:
        pass
    raise ValueError('no schema alternative matches')
  kind = schema.get('type')
  valid = {'object': isinstance(value, dict), 'string': isinstance(value, str),
           'integer': type(value) is int, 'number': type(value) in (float, int) and math.isfinite(value),
           'boolean': type(value) is bool, 'null': value is None}
  if kind and not valid[kind]:
    raise ValueError('wrong type: ' + kind)
  if 'const' in schema and value != schema['const']:
    raise ValueError('wrong constant')
  if 'enum' in schema and value not in schema['enum']:
    raise ValueError('invalid enum')
  if type(value) in (int, float):
    if 'minimum' in schema and value < schema['minimum']:
      raise ValueError('below minimum')
    if 'exclusiveMinimum' in schema and value <= schema['exclusiveMinimum']:
      raise ValueError('below exclusive minimum')
  if isinstance(value, str):
    if len(value) < schema.get('minLength', 0) or len(value) > schema.get('maxLength', 1000000):
      raise ValueError('string length')
    if 'pattern' in schema and not re.search(schema['pattern'], value):
      raise ValueError('invalid string pattern')
  if isinstance(value, dict):
    if set(schema.get('required', [])) - set(value):
      raise ValueError('missing required fields')
    for key, item in value.items():
      child = schema.get('properties', {}).get(key, schema.get('additionalProperties', True))
      if child is False:
        raise ValueError('unexpected field: ' + key)
      if isinstance(child, dict):
        validate(item, child, root)


def validate_sample(sample):
  validate(sample, json.loads((HERE / 'schema-v2.json').read_text()))
  for group in ('probes', 'before', 'after'):
    for item in sample[group].values():
      if (item['status'] == 'ok') != (item['value'] is not None):
        raise ValueError('status/value mismatch')
  if sample['probes'].get('collector.euid', {}).get('value') != 0:
    raise ValueError('root probe did not execute')
  if datetime.datetime.fromisoformat(sample['ended_utc']) < datetime.datetime.fromisoformat(sample['started_utc']):
    raise ValueError('sample ends before start')


def ssh_argv(host, user, identity, known_hosts, remote_args, password_stdin=False):
  if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.-]*', host) or not re.fullmatch(r'[a-z_][a-z0-9_-]*', user):
    raise ValueError('use a plain hostname and user; no SSH aliases/options')
  command = shlex.join(['sudo', '-n', '--', '/usr/bin/python3', '-I', '-', 'probe'] + remote_args)
  if password_stdin:
    bootstrap = 'import sys; source=sys.argv.pop(1); exec(compile(source, "<stdin>", "exec"), {"__name__": "__main__", "__file__": "<stdin>"})'
    # Read password and complete source before sudo; Python code uses -c, so
    # sudo owns password stdin and the source never competes for that stream.
    command = ('IFS= read -r password && code=$(cat) && '
               "printf '%s\\n' \"$password\" | sudo -S -p '' -- /usr/bin/python3 -I -c "
               + shlex.quote(bootstrap) + ' "$code" probe ' + shlex.join(remote_args))
  return ['/usr/bin/ssh', '-F', '/dev/null', '-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
          '-o', 'UserKnownHostsFile=' + str(Path(known_hosts).resolve()), '-o', 'IdentitiesOnly=yes',
          '-o', 'ClearAllForwardings=yes', '-o', 'ForwardAgent=no', '-o', 'ForwardX11=no',
          '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2',
          '-i', str(Path(identity).resolve()), user + '@' + host,
          command]


def main():
  ap = argparse.ArgumentParser(description=__doc__)
  sub = ap.add_subparsers(dest='mode', required=True)
  probe = sub.add_parser('probe')
  probe.add_argument('--metadata-b64', required=True)
  probe.add_argument('--bench', action='store_true')
  record = sub.add_parser('record')
  for name in ('host', 'user', 'identity', 'known-hosts', 'cohort', 'label', 'experiment', 'trial', 'conditions', 'candidate', 'out'):
    record.add_argument('--' + name, required=True)
  record.add_argument('--bench', action='store_true')
  record.add_argument('--sudo-password-stdin', action='store_true', help='read one authorized sudo password line from stdin; never from argv or environment')
  check = sub.add_parser('validate')
  check.add_argument('sample', type=Path)
  args = ap.parse_args()
  if args.mode == 'probe':
    metadata = json.loads(base64.b64decode(args.metadata_b64, validate=True))
    print(json.dumps(collect(metadata, args.bench), allow_nan=False))
  elif args.mode == 'validate':
    validate_sample(json.loads(args.sample.read_text()))
    print('valid v2 sample')
  else:
    payload = Path(__file__).read_bytes()
    metadata = {key: getattr(args, key) for key in ('cohort', 'label', 'experiment', 'trial', 'conditions', 'candidate')}
    metadata['probe_sha256'] = hashlib.sha256(payload).hexdigest()
    metadata['transport'] = ('ssh-key-strict-hostkey-sudo-S-framed' if args.sudo_password_stdin
                             else 'ssh-key-strict-hostkey-sudo-n')
    schema = json.loads((HERE / 'schema-v2.json').read_text())
    validate(metadata, schema['properties']['metadata'])
    remote_args = ['--metadata-b64', base64.b64encode(json.dumps(metadata).encode()).decode()]
    if args.bench:
      remote_args.append('--bench')
    argv = ssh_argv(args.host, args.user, args.identity, args.known_hosts, remote_args, args.sudo_password_stdin)
    if args.sudo_password_stdin:
      password = sys.stdin.buffer.readline(4096)
      if not password.endswith(b'\n') or password in (b'\n', b'\r\n') or b'\x00' in password:
        raise ValueError('one nonempty password line required')
      payload = password + payload
    proc = subprocess.run(argv, input=payload, capture_output=True, timeout=120, check=True)
    sample = json.loads(proc.stdout)
    validate_sample(sample)
    if sample['metadata'] != metadata:
      raise ValueError('probe metadata mismatch')
    out = Path(args.out) / metadata['cohort']
    out.mkdir(parents=True, exist_ok=True)
    target = out / (sample['sample_id'] + '.json')
    with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w', encoding='utf-8') as fh:
      fh.write(json.dumps(sample, indent=2, allow_nan=False) + '\n')
    print(target)


if __name__ == '__main__':
  try:
    main()
  except (ValueError, OSError, subprocess.SubprocessError) as exc:
    # Do not dump command output, credentials, or remote environment on failure.
    print('pi-metrics: ' + type(exc).__name__ + ': collection/validation failed; no sample accepted', file=sys.stderr)
    sys.exit(1)
