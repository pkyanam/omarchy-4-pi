#!/usr/bin/python3
"""Offline-first, exact-BTF UART RAM-counter tracing candidate for parent review."""
import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
BTF_SHA256 = 'f8711335d174e735928d53a899d57e082b2b68f077333036c505ef887bd22959'


class BTF:
  """Read captured little-endian raw BTF; never consume an ELF or target memory."""
  def __init__(self, path):
    raw = Path(path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != BTF_SHA256:
      raise RuntimeError('BTF hash differs from parent-captured running kernel')
    magic, version, flags, hdr, off, length, strings, slen = struct.unpack_from('<HBBIIIII', raw)
    if (magic, version, flags) != (0xeb9f, 1, 0):
      raise RuntimeError('Unexpected BTF header')
    self.strings = raw[hdr + strings:hdr + strings + slen]
    self.types = [None]
    pos, end = hdr + off, hdr + off + length
    while pos < end:
      name, info, target = struct.unpack_from('<III', raw, pos)
      pos += 12
      kind, count, bitfield = (info >> 24) & 31, info & 65535, info >> 31
      sizes = {1:4, 2:0, 3:12, 4:12*count, 5:12*count, 6:8*count,
               7:0, 8:0, 9:0, 10:0, 11:0, 12:0, 13:8*count,
               14:4, 15:12*count, 16:0, 17:4, 18:0, 19:12*count}
      if kind not in sizes or pos + sizes[kind] > end:
        raise RuntimeError('Unsupported/truncated BTF type')
      data = raw[pos:pos + sizes[kind]]
      self.types.append(dict(name=self.string(name), kind=kind, count=count,
                             bitfield=bitfield, target=target, data=data))
      pos += sizes[kind]
    if pos != end:
      raise RuntimeError('Invalid BTF type boundary')

  def string(self, offset):
    return self.strings[offset:self.strings.index(b'\0', offset)].decode('ascii')

  def named(self, name, kind):
    matches = [(i, t) for i, t in enumerate(self.types) if t and t['name'] == name and t['kind'] == kind]
    if len(matches) != 1:
      raise RuntimeError(f'BTF missing/ambiguous {name}, kind {kind}')
    return matches[0]

  def resolve(self, index):
    t = self.types[index]
    while t['kind'] in (8, 9, 10, 11, 18):
      index = t['target']
      t = self.types[index]
    return index, t

  def member(self, struct_name, member):
    _, t = self.named(struct_name, 4)
    matches = []
    for n, typ, bits in struct.iter_unpack('<III', t['data']):
      if self.string(n) == member:
        width = bits >> 24 if t['bitfield'] else 0
        offset = bits & 0xffffff if t['bitfield'] else bits
        if width or offset % 8:
          raise RuntimeError('Bitfield/unaligned member refused')
        matches.append((offset // 8, typ))
    if len(matches) != 1:
      raise RuntimeError(f'Missing/ambiguous member {struct_name}.{member}')
    return matches[0]

  def scalar(self, root, path):
    total = 0
    for field in path.split('.'):
      offset, typ = self.member(root, field)
      total += offset
      _, t = self.resolve(typ)
      root = t['name']
    if t['kind'] != 1:
      raise RuntimeError('Only integer RAM scalars allowed')
    encoding = struct.unpack('<I', t['data'])[0]
    if encoding & 1 << 24 or (encoding >> 16) & 255 or encoding & 255 != t['target'] * 8:
      raise RuntimeError('Signed/partial-width scalar refused')
    return {'offset': total, 'bytes': t['target'], 'type': t['name']}

  def signature(self, name):
    _, f = self.named(name, 12)
    p = self.types[f['target']]
    if p['kind'] != 13:
      raise RuntimeError('Expected function prototype')
    def describe(index):
      if index == 0:
        return 'void'
      _, t = self.resolve(index)
      if t['kind'] == 2:
        return describe(t['target']) + '*'
      return t['name']
    return {'return': describe(p['target']), 'args': [describe(t) for _, t in struct.iter_unpack('<II', p['data'])]}


# No per-character callback, instruction offset, raw address or return probe.
SIGNATURES = {
  'serial8250_start_tx': ('void', ['uart_port*']),
  'serial8250_tx_chars': ('void', ['uart_8250_port*']),
  'serial8250_stop_tx': ('void', ['uart_port*']),
  'serial8250_rx_chars': ('short unsigned int', ['uart_8250_port*', 'short unsigned int']),
  'serial8250_modem_status': ('unsigned int', ['uart_8250_port*']),
  'uart_write_wakeup': ('void', ['uart_port*']),
  'uart_handle_cts_change': ('void', ['uart_port*', '_Bool']),
}
FIELDS = ['line', 'hw_stopped', 'icount.tx', 'icount.rx', 'icount.cts',
          'icount.frame', 'icount.parity', 'icount.overrun', 'icount.brk', 'icount.buf_overrun']


def evidence(path):
  btf = BTF(path)
  offset, typ = btf.member('uart_8250_port', 'port')
  if offset != 0 or btf.resolve(typ)[1]['name'] != 'uart_port':
    raise RuntimeError('uart_8250_port.port is not a leading uart_port')
  signatures = {name: btf.signature(name) for name in SIGNATURES}
  for name, (ret, args) in SIGNATURES.items():
    if signatures[name] != {'return': ret, 'args': args}:
      raise RuntimeError(f'Unexpected exact BTF signature: {name}: {signatures[name]}')
  fields = {name: btf.scalar('uart_port', name) for name in FIELDS}
  for name, f in fields.items():
    if f['bytes'] != (1 if name == 'hw_stopped' else 4):
      raise RuntimeError(f'Unexpected scalar width: {name}')
  return {'btf_sha256': BTF_SHA256, 'fields': fields, 'signatures': signatures}


DEVICE_PATH = '/sys/devices/platform/soc/fe215040.serial/fe215040.serial:0/fe215040.serial:0.0/serial0/serial0-0'


def load_identity(path, live=False):
  identity = json.loads(Path(path).read_text())
  # Parent must obtain this from current-boot registration evidence. tty class
  # absence and the serial0 controller name do not prove uart_port.line.
  if (set(identity) != {'device_path', 'line', 'proof', 'boot_id', 'source_evidence_sha256'} or
      identity.get('device_path') != DEVICE_PATH or
      type(identity.get('line')) is not int or not 1 <= identity['line'] < 256 or
      identity.get('proof') != 'current-boot UART registration maps fe215040.serial to ttyS' + str(identity['line']) or
      not isinstance(identity.get('boot_id'), str) or
      not re.fullmatch(r'[0-9a-f-]{36}', identity['boot_id']) or
      not re.fullmatch(r'[0-9a-f]{64}', identity.get('source_evidence_sha256', ''))):
    raise RuntimeError('Need parent-reviewed current-boot UART line identity evidence')
  if live:
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != identity['boot_id']:
      raise RuntimeError('Line identity evidence is from a different boot')
    if str(Path('/sys/bus/serial/devices/serial0-0').resolve(strict=True)) != DEVICE_PATH:
      raise RuntimeError('Serial device path changed')
  return identity


def probes(layout):
  fields = [(n.replace('.', '_'), f"+{f['offset']}(%x0):u{f['bytes'] * 8}", f['bytes'], 0)
            for n, f in layout['fields'].items()]
  result = []
  for symbol in SIGNATURES:
    extra = []
    if symbol == 'uart_handle_cts_change':
      extra = [('active', '%x1:u8', 1, 0)]
    # No LSR/MSR reads: RX/error information comes only from RAM icount.
    result.append((symbol, 'p', symbol, None, fields + extra))
  return result


def run():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--btf', type=Path, help='Captured exact running BTF; live default /sys/kernel/btf/vmlinux')
  parser.add_argument('--identity', type=Path, help='Parent-reviewed current-boot identity JSON; never infer ttyS1')
  modes = parser.add_mutually_exclusive_group()
  modes.add_argument('--validate-probes', action='store_true')
  modes.add_argument('--execute', action='store_true')
  parser.add_argument('--expected-formats')
  parser.add_argument('--output', type=Path)
  args = parser.parse_args()
  live = args.validate_probes or args.execute
  if live and not args.identity:
    parser.error('Live modes require --identity from current-boot registration evidence')
  btf_path = args.btf or Path('/sys/kernel/btf/vmlinux')
  if live and btf_path != Path('/sys/kernel/btf/vmlinux'):
    parser.error('Live mode must independently verify /sys/kernel/btf/vmlinux')
  if not args.btf and not live:
    print(json.dumps({'status': 'offline plan', 'btf_sha256': BTF_SHA256,
                      'window_seconds': 12, 'line': 'UNPROVEN: parent current-boot identity required',
                      'next': '--btf CAPTURED_BTF for exact derived layout; no probes or rebind'}, indent=2))
    return 0
  layout = evidence(btf_path)
  identity = load_identity(args.identity, live) if args.identity else None
  contract = {'layout': layout, 'identity': identity, 'filter': f"line == {identity['line']}" if identity else None,
              'probes': probes(layout)}
  if not live:
    print(json.dumps(contract, indent=2))
    return 0
  for name, expected in {
    'bluetooth-scalar-trace.py': '081de23982d893a200e0725de55a283631ae165ee87c0beb34206f7ed5db5b4a',
    'bluetooth-transport-trace.py': '1c1e9acc5ccd51b4ed8185f2239069ead398771478b77239edf42d9f20d694c1',
  }.items():
    if hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest() != expected:
      raise RuntimeError('Adjacent lifecycle helper changed; parent coordination required')
  spec = importlib.util.spec_from_file_location('bt_scalar', Path(__file__).with_name('bluetooth-scalar-trace.py'))
  scalar = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(scalar)
  scalar.PROBES = probes(layout)
  scalar.base.DISCOVER = set(SIGNATURES) | set(scalar.base.DISCOVER)
  original_digest = scalar.digest
  scalar.digest = lambda formats: original_digest({'formats': formats, 'contract': contract})

  class Capture(scalar.Capture):
    def save(self, name, value):
      if name == 'plan.json':
        value = dict(value, fetches='Exact-BTF non-I/O RAM line/hw_stopped/icount and CTS bool only',
                     uart_contract=contract)
      super().save(name, value)

    def check_contract(self):
      if evidence(Path('/sys/kernel/btf/vmlinux')) != layout or load_identity(args.identity, True) != identity:
        raise RuntimeError('BTF/line identity changed')

    def install(self):
      self.check_contract()
      super().install()
      self.save('uart-contract.json', contract)
      for name, *_ in scalar.PROBES:
        event = self.instance / 'events' / self.group / name
        scalar.base.write(event / 'filter', contract['filter'])
        if scalar.base.read(event / 'filter').strip() != contract['filter']:
          raise RuntimeError('Installed line filter differs')
      self.save('filters.json', {n: contract['filter'] for n, *_ in scalar.PROBES})

    def run_window(self, before):
      self.check_contract()
      for name, *_ in scalar.PROBES:
        if scalar.base.read(self.instance / 'events' / self.group / name / 'filter').strip() != contract['filter']:
          raise RuntimeError('Line filter changed before rebind')
      super().run_window(before)

  scalar.Capture = Capture
  sys.argv = [sys.argv[0], '--execute' if args.execute else '--validate-probes']
  if args.output:
    sys.argv += ['--output', str(args.output)]
  if args.expected_formats:
    sys.argv += ['--expected-formats', args.expected_formats]
  return scalar.main()


if __name__ == '__main__':
  try:
    sys.exit(run())
  except (OSError, RuntimeError, ValueError, KeyError, struct.error) as exc:
    print(f'Refused/failed: {exc}', file=sys.stderr)
    sys.exit(1)
