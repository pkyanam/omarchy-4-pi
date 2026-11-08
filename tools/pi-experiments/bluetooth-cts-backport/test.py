#!/usr/bin/python3
"""Bounded offline production-function tests; no kernel/module compilation."""
import argparse
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('replay', HERE / 'replay.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
IMAGE = 'sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2'

def generate(source, out):
  text = source.read_text()
  # Compile the real source prefix containing every changed production function
  # and the unchanged RS485 TX callbacks. Only Linux includes are replaced.
  prefix = text[:text.index('static int bcm2835aux_serial_probe')]
  prefix = re.sub(r'^#include .*\n', '', prefix, flags=re.M)
  (out / 'production.inc').write_text('#include "boundary.h"\n' + prefix)
  callbacks = ''
  for name, signature, call, default in [
    ('set_termios', 'struct uart_port *p, struct ktermios *t, const struct ktermios *o', 'p,t,o', 'serial8250_do_set_termios'),
    ('set_mctrl', 'struct uart_port *p, unsigned int m', 'p,m', 'serial8250_do_set_mctrl'),
    ('throttle', 'struct uart_port *p', 'p', None),
    ('unthrottle', 'struct uart_port *p', 'p', None),
    ('rs485_config', 'struct uart_port *p, struct ktermios *t, struct serial_rs485 *s', 'p,t,s', 'serial8250_em485_config')]:
    match = re.search(r'up.port.' + name + r' = (\w+);', text)
    callback = match[1] if match else default
    ret = 'int' if name == 'rs485_config' else 'void'
    wrapper = {'set_termios':'termios', 'set_mctrl':'mctrl', 'rs485_config':'rs485'}.get(name,name)
    body = ('return ' if ret == 'int' else '') + callback + '(' + call + ');' if callback else '(void)p;'
    callbacks += f'static {ret} apply_{wrapper}({signature}) {{ {body} }}\n'
  (out / 'callbacks.inc').write_text(callbacks)
  for name in ['boundary.h', 'flow-test.c']:
    shutil.copyfile(HERE / name, out / name)

def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--output', type=Path, required=True)
  args = parser.parse_args()
  out = args.output.resolve()
  assert out.is_relative_to(r.DEFAULT) and out != r.DEFAULT
  patched = r.replay(out)
  manifest = __import__('json').loads((HERE / 'manifest.json').read_text())
  for name, source in [('base', r.ROOT / manifest['source_root'] / manifest['driver']), ('fixed', patched)]:
    work = out / name
    work.mkdir()
    generate(source, work)
  code = '''set -eu
export TMPDIR=/work
cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.swap.max
cc --version
for mode in base fixed; do
  cd /work/$mode
  cc -std=gnu11 -O0 -g -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-parameter flow-test.c -o flow-test
  set +e
  ./flow-test > result.log 2>&1
  rc=$?
  set -e
  cat result.log
  if [[ $mode == base ]]; then [[ $rc == 1 ]]; else [[ $rc == 0 ]]; fi
done
cd /work
dtc -@ -I dts -O dtb -o aux.dtbo /inputs/pftf-aux-rtscts.dtso
fdtoverlay -i /inputs/current.fdt -o opt-in.fdt aux.dtbo
for f in memory.peak memory.events cpu.stat; do cat /sys/fs/cgroup/$f; done
'''
  container_name = 'bt-cts-backport-' + uuid.uuid4().hex
  cmd = ['docker', 'run', '--name', container_name, '--rm', '--pull=never', '--read-only', '--network=none', '--cpus=.25',
         '--memory=256m', '--memory-swap=256m', '--pids-limit=32', '--cap-drop=ALL',
         '--security-opt=no-new-privileges', '--entrypoint=/bin/bash',
         '-v', str(out) + ':/work', '-v', str(HERE / 'pftf-aux-rtscts.dtso') + ':/inputs/pftf-aux-rtscts.dtso:ro',
         '-v', str(r.ROOT / 'build/upstream-pi/stable-4.5/bt-cts-candidate/parent-window-1/bt-cts-window-1/current.fdt') + ':/inputs/current.fdt:ro',
         IMAGE, '-c', code]
  with (out / 'test.log').open('w') as log:
    try:
      subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=60, check=True)
    except subprocess.TimeoutExpired:
      # A killed Docker client does not necessarily stop its container.
      subprocess.run(['docker', 'rm', '-f', container_name], stdout=log,
                     stderr=subprocess.STDOUT, timeout=10, check=False)
      raise
  # Ensure applying opt-in leaves every other node/property unchanged.
  original = r.fdt_nodes(r.ROOT / 'build/upstream-pi/stable-4.5/bt-cts-candidate/parent-window-1/bt-cts-window-1/current.fdt')
  applied = r.fdt_nodes(out / 'opt-in.fdt')
  assert applied['/soc/serial@7e215040'].pop('uart-has-rtscts') == b''
  assert original == applied
  print('PASS: base red, fixed green, overlay changes only AUX opt-in; see', out / 'test.log')

if __name__ == '__main__':
  main()
