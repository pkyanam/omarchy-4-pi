"""Conservative Pi 4 KMS setup; never evaluate includes or guess boot filters."""

import argparse
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

BEGIN = "# BEGIN OMARCHY PI4 KMS"
END = "# END OMARCHY PI4 KMS"
KMS = re.compile(r"vc4-kms-v3d(?:-pi4)?(?:,|$)")
MODELS = {"pi0", "pi0w", "pi02", "pi1", "pi2", "pi3", "pi3+", "pi4", "pi400", "pi5", "pi500", "pi500+", "cm4", "cm5"}
SETTINGS = ["[all]", "[pi4]", "max_framebuffers=2", "disable_fw_kms_setup=1", "dtoverlay=", "dtparam=audio=on"]


class Refused(ValueError):
  pass


def select_config(explicit=None, candidates=None):
  paths = [Path(explicit)] if explicit else list(candidates or (Path("/boot/config.txt"), Path("/boot/firmware/config.txt")))
  present = []
  for path in paths:
    if path.is_symlink():
      raise Refused(f"Boot config is a symlink: {path}; select the real file explicitly.")
    if path.is_file():
      if not any(os.path.samefile(path, other) for other in present):
        present.append(path)
  if len(present) != 1:
    raise Refused("Expected one regular boot config; missing/ambiguous paths require an explicit OMARCHY_RPI_CONFIG_PATH.")
  return present[0]


def proposed(original):
  text = original.decode("utf-8")
  if "\x00" in text:
    raise Refused("Boot config contains NUL bytes.")
  lines = text.splitlines(keepends=True)
  starts = [i for i, line in enumerate(lines) if BEGIN in line]
  ends = [i for i, line in enumerate(lines) if END in line]
  if starts or ends:
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
      raise Refused("Malformed or repeated managed KMS block; review manually.")
    if lines[starts[0]].strip() != BEGIN or lines[ends[0]].strip() != END:
      raise Refused("Malformed managed KMS markers; review manually.")
    body = [line.strip() for line in lines[starts[0] + 1:ends[0]]]
    if body not in (SETTINGS + ["[all]"], SETTINGS + ["dtoverlay=vc4-kms-v3d", "[all]"]):
      raise Refused("Managed KMS block was edited; preserve owner settings and review manually.")
    if any(line.strip() for line in lines[ends[0] + 1:]):
      raise Refused("Settings follow the managed KMS block; review their priority manually.")
    lines = lines[:starts[0]]

  model_active = True
  conditional = False
  disabled = False
  overlays = []
  for number, raw in enumerate(lines, 1):
    line = raw.split("#", 1)[0].strip()
    if not line:
      continue
    if re.match(r"include(?:\s|=|$)", line, re.I):
      raise Refused(f"Config include at line {number}; review the complete boot config manually.")
    section = re.fullmatch(r"\[([^\]]+)\]", line)
    if section:
      name = section[1].lower()
      if name == "all":
        model_active, conditional, disabled = True, False, False
      elif name == "none":
        disabled = True
      elif name in MODELS:
        model_active = name == "pi4"
      else:
        # Display, serial, GPIO, EDID, tryboot and unknown filters can combine
        # with a model filter. Only [all] proves those conditions are cleared.
        conditional = True
      continue
    assignment = re.fullmatch(r"([a-zA-Z0-9_]+)\s*=\s*(.*)", line)
    if not assignment:
      if line.startswith("["):
        raise Refused(f"Malformed boot filter at line {number}.")
      continue
    key, value = assignment.groups()
    related = key in {"max_framebuffers", "disable_fw_kms_setup"} or (
      key == "dtoverlay" and value.startswith(("vc4-kms", "vc4-fkms"))) or (
      key == "dtparam" and re.search(r"(?:^|,)\s*audio(?:=|,|$)", value))
    if not related or disabled or not model_active:
      continue
    if conditional:
      raise Refused(f"Conditional KMS/audio setting at line {number}; cannot determine Pi 4 applicability safely.")
    if len(line) > 98:
      raise Refused(f"KMS/audio setting exceeds the firmware line limit at line {number}.")
    if key == "dtoverlay":
      if not KMS.match(value):
        raise Refused(f"Conflicting graphics overlay at line {number}; full KMS needs manual review.")
      if re.search(r"(?:^|,)\s*noaudio(?:=|,|$)", value):
        raise Refused("Existing full KMS explicitly disables HDMI audio; review it manually.")
      overlays.append(value)
  if len(overlays) > 1:
    raise Refused("More than one applicable full KMS overlay; avoid duplicate overlay loading and review manually.")

  # Scalars and base DT parameters are last-wins. Reset every filter, target
  # Pi 4 only, and end any overlay-parameter context before enabling audio.
  # Leave a single existing applicable KMS overlay and all its parameters in
  # place; an inactive [pi5] overlay never satisfies the Pi 4 requirement.
  block = [BEGIN] + SETTINGS
  if not overlays:
    block.append("dtoverlay=vc4-kms-v3d")
  block.extend(("[all]", END))
  return ("".join(lines).rstrip("\r\n") + "\n\n" + "\n".join(block) + "\n").encode()


def apply(path):
  info = path.stat()
  if not stat.S_ISREG(info.st_mode):
    raise Refused("Boot config must be a regular file.")
  original = path.read_bytes()
  updated = proposed(original)
  if updated == original:
    print(f"Pi 4 KMS config already current: {path}")
    return
  backup = path.with_name(path.name + ".omarchy-before-kms")
  if backup.is_symlink() or (backup.exists() and not backup.is_file()):
    raise Refused("Recovery copy is not a regular file; review manually.")
  if backup.exists() and backup.read_bytes() != original:
    descriptor, name = tempfile.mkstemp(prefix=backup.name + "-", dir=path.parent)
    backup = Path(name)
  else:
    descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, stat.S_IMODE(info.st_mode)) if not backup.exists() else None
  if descriptor is not None:
    with os.fdopen(descriptor, "wb") as stream:
      stream.write(original)
      stream.flush()
      os.fsync(stream.fileno())
  descriptor, name = tempfile.mkstemp(prefix=".omarchy-kms-", dir=path.parent)
  try:
    with os.fdopen(descriptor, "wb") as stream:
      os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode))
      if (os.fstat(stream.fileno()).st_uid, os.fstat(stream.fileno()).st_gid) != (info.st_uid, info.st_gid):
        os.fchown(stream.fileno(), info.st_uid, info.st_gid)
      stream.write(updated)
      stream.flush()
      os.fsync(stream.fileno())
    if path.is_symlink() or path.read_bytes() != original or path.stat().st_ino != info.st_ino:
      raise Refused("Boot config changed during setup; retry after reviewing it.")
    os.replace(name, path)
  finally:
    Path(name).unlink(missing_ok=True)
  print(f"Configured Pi 4 KMS: {path}; backup: {backup}; reboot required")


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--path")
  args = parser.parse_args()
  try:
    apply(select_config(args.path))
  except (OSError, ValueError) as error:
    print(f"Refusing Pi firmware changes: {error}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  sys.exit(main())
