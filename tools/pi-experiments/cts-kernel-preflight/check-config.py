#!/usr/bin/env python3
"""Fail closed against the reviewed 32.1 configuration and every symbol value."""
import hashlib
from pathlib import Path
import re
import sys

SOURCE = "41f89661b0af2c747e122f36417be7da2e7fb69049817c00404acf35fbef47a4"
RESOLVED = "3b12d3dd8d8b0b24ab95ef96bb1b3388d2440a5bda069ecd74f3c7984a2fd51d"


def symbols(path):
  values = {}
  for line in path.read_text().splitlines():
    match = re.fullmatch(r"(CONFIG_\w+)=(.+)", line)
    disabled = re.fullmatch(r"# (CONFIG_\w+) is not set", line)
    if match or disabled:
      key, value = match.groups() if match else (disabled[1], "n")
      if key in values:
        raise ValueError(f"duplicate symbol: {key}")
      values[key] = value
    elif line and not line.startswith("#"):
      raise ValueError(f"unrecognized config line: {line}")
  if not values:
    raise ValueError("empty configuration")
  return values


def check(source, resolved):
  baseline = Path(__file__).with_name("reviewed-resolved.config")
  for path, expected in ((source, SOURCE), (baseline, RESOLVED)):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
      raise ValueError(f"reviewed input hash mismatch: {path}")
  reference = symbols(baseline)
  for path in (source, resolved):
    actual = symbols(path)
    changes = {key: (reference.get(key), actual.get(key))
               for key in reference.keys() | actual.keys()
               if reference.get(key) != actual.get(key)}
    if changes:
      raise ValueError(f"CONFIG drift in {path}: {changes}")
  print(f"Reviewed config equivalence passed: {len(reference)} symbols; comments/order only")


if __name__ == "__main__":
  try:
    check(*(Path(arg) for arg in sys.argv[1:]))
  except (ValueError, OSError) as error:
    sys.exit(str(error))
