#!/usr/bin/env python3
"""Replay the inactive, pinned research series into a fresh source directory."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--archive', type=Path, required=True)
  parser.add_argument('--output', type=Path, required=True)
  args = parser.parse_args()
  root = Path(__file__).resolve().parent
  digest = hashlib.sha256()
  with args.archive.open('rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
      digest.update(chunk)
  if digest.hexdigest() != '87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953':
    parser.error('requires the exact Linux 7.3 source archive')
  args.output.mkdir(parents=False, exist_ok=False)
  with tarfile.open(args.archive, 'r|xz') as archive:
    for member in archive:
      relative = member.name.removeprefix('linux-7.3/')
      if member.isfile() and relative.startswith(('drivers/platform/raspberrypi/', 'include/linux/raspberrypi/')):
        destination = args.output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(archive.extractfile(member).read())
  for name in (root / 'patches/series').read_text().splitlines():
    with (root / 'patches' / name).open() as patch:
      subprocess.run(['patch', '--batch', '--fuzz=0', '-p1'], cwd=args.output, stdin=patch, check=True)
  shutil.copyfile(root / 'external-lifecycle-module.Makefile', args.output / 'Makefile')
  print(args.output)


if __name__ == '__main__':
  main()
