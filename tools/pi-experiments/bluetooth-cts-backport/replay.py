#!/usr/bin/python3
"""Offline exact-source replay. Writes only a fresh ignored candidate directory."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DEFAULT = ROOT / 'build/upstream-pi/stable-4.5/bt-cts-backport-candidate'

def digest(path):
  return hashlib.sha256(path.read_bytes()).hexdigest()

def fdt_nodes(path):
  data = path.read_bytes()
  magic, total, off, strings, reserve, version, compat, cpu, ssize, size = struct.unpack_from('>10I', data)
  assert magic == 0xd00dfeed and total == len(data) and version >= 17
  names = data[strings:strings + ssize]
  end = off + size
  stack, nodes = [], {}
  while off < end:
    token, = struct.unpack_from('>I', data, off)
    off += 4
    if token == 1:
      stop = data.index(0, off)
      stack.append(data[off:stop].decode())
      off = (stop + 4) & ~3
      nodes['/' + '/'.join(stack[1:])] = {}
    elif token == 2:
      stack.pop()
    elif token == 3:
      length, name = struct.unpack_from('>II', data, off)
      off += 8
      key = names[name:names.index(0, name)].decode()
      nodes['/' + '/'.join(stack[1:])][key] = data[off:off + length]
      off = (off + length + 3) & ~3
    elif token == 9:
      return nodes
    else:
      assert token == 4, token
  raise ValueError('missing FDT end')

def cells(value):
  return list(struct.unpack('>' + 'I' * (len(value) // 4), value))

def route(path):
  nodes = fdt_nodes(path)
  phandles = {cells(v['phandle'])[0]: k for k, v in nodes.items() if 'phandle' in v}
  candidates = [k for k, v in nodes.items() if b'brcm,bcm2835-aux-uart\0' in v.get('compatible', b'')]
  assert len(candidates) == 1
  aux = candidates[0]
  v = nodes[aux]
  assert v['status'] == b'okay\0' and 'uart-has-rtscts' not in v and 'cts-gpios' not in v
  pins = nodes[phandles[cells(v['pinctrl-0'])[0]]]
  assert cells(pins['brcm,pins']) == [32, 33, 30, 31]
  assert cells(pins['brcm,function']) == [2]
  bt = nodes[aux + '/bluetooth']
  assert bt['status'] == b'okay\0' and b'brcm,bcm43438-bt\0' in bt['compatible']
  shutdown = cells(bt['shutdown-gpios'])
  expander = phandles[shutdown[0]]
  assert shutdown[1:] == [0, 0]
  assert b'raspberrypi,firmware-gpio\0' in nodes[expander]['compatible']
  assert nodes[expander]['gpio-line-names'].split(b'\0')[0] == b'BT_ON'
  return {'aux_path': aux, 'pin_numbers': cells(pins['brcm,pins']), 'function': 2,
          'shutdown_controller': expander, 'shutdown_offset': 0, 'shutdown_active_low': False,
          'max_speed': cells(bt['max-speed'])[0], 'current_fdt_sha256': digest(path)}

def replay(output):
  m = json.loads((HERE / 'manifest.json').read_text())
  for path, expected in m['inputs'].items():
    assert digest(ROOT / path) == expected, 'input changed: ' + path
  patch = HERE / '0001-serial-8250-bcm2835aux-hardware-flow.patch'
  assert digest(patch) == m['patch_sha256']
  output.mkdir(exist_ok=False)
  source = ROOT / m['source_root'] / m['driver']
  target = output / m['driver']
  target.parent.mkdir(parents=True)
  target.write_bytes(source.read_bytes())
  assert digest(target) == m['before_sha256']
  p = subprocess.run(['patch', '--batch', '--fuzz=0', '-p1', '-i', str(patch)], cwd=output,
                     capture_output=True, text=True, check=True)
  (output / 'patch.log').write_text(p.stdout + p.stderr)
  assert 'offset' not in p.stdout + p.stderr and 'fuzz' not in p.stdout + p.stderr
  assert digest(target) == m['after_sha256']
  fdt = next(ROOT / p for p in m['inputs'] if p.endswith('/current.fdt'))
  mapping = route(fdt)
  (output / 'route.json').write_text(json.dumps(mapping, indent=2) + '\n')
  # target-path avoids reliance on firmware labels/symbols. No other DT property changes.
  overlay = '/dts-v1/;\n/plugin/;\n/ {\n  fragment@0 {\n    target-path = "' + mapping['aux_path'] + '";\n    __overlay__ {\n      uart-has-rtscts;\n    };\n  };\n};\n'
  assert overlay == (HERE / 'pftf-aux-rtscts.dtso').read_text()
  print('PASS: pinned inputs, zero-fuzz/zero-offset replay, exact output hash, current FDT route')
  return target

if __name__ == '__main__':
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--output', type=Path, required=True)
  args = parser.parse_args()
  out = args.output.resolve()
  assert out.is_relative_to(DEFAULT) and out != DEFAULT, 'use a fresh child of ignored candidate root'
  replay(out)
