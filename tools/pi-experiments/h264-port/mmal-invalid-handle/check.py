#!/usr/bin/env python3
"""Exercise the actual MMAL submit/cleanup bodies across the VCSM boundary."""
import argparse
from pathlib import Path
import subprocess


def function(source, name):
  start = source.index('int ' + name + '(')
  opening = source.index('{', start)
  depth, end = 1, opening + 1
  while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
  return source[start:end]


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('source', type=Path)
  parser.add_argument('--output', type=Path, required=True)
  args = parser.parse_args()
  args.output.mkdir(exist_ok=False)
  unit = Path(__file__).parent
  source = args.source.read_text()
  bodies = '\n'.join(function(source, name) for name in ('vchiq_mmal_submit_buffer', 'mmal_vchi_buffer_cleanup'))
  generated = args.output / 'check.c'
  generated.write_text((unit / 'boundary.c').read_text().replace('/* PRODUCTION_FUNCTIONS */', bodies))
  binary = args.output / 'check'
  subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                  '-fno-sanitize-recover=all', str(generated), '-o', str(binary)], check=True)
  subprocess.run([str(binary)], check=True, timeout=10)


if __name__ == '__main__':
  main()
