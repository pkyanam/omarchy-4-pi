"""Create and retire only the image factory's own disk-backed workspace."""

import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile


def plain_path(value):
  path = Path(os.path.abspath(value))
  # Check each component before resolving: resolving first hides symlink input.
  for component in (path, *path.parents):
    if component.is_symlink():
      raise ValueError(f"symlink is not allowed in an image storage path: {component}")
  return path


def overlaps(left, right):
  return left == right or left in right.parents or right in left.parents


def create(parent, repo, output, size_gib):
  parent, repo, output = map(plain_path, (parent, repo, output))
  if parent in {Path("/"), Path.home()} or overlaps(parent, repo) or overlaps(parent, output):
    raise ValueError("workspace parent must be separate from root, source checkout, and output")
  parent.mkdir(parents=True, exist_ok=True)
  output.mkdir(parents=True, exist_ok=True)
  fstype = subprocess.check_output(
    ["findmnt", "--noheadings", "--output", "FSTYPE", "--target", str(parent)], text=True
  ).strip()
  if fstype not in {"ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "zfs", "bcachefs"}:
    raise ValueError("image workspace must use disk-backed storage")
  # Allow for the sparse image becoming allocated, rootfs/package/source caches,
  # and worst-case compressed output. This is a preflight floor, not a guarantee.
  gib = 1024 ** 3
  same_disk = parent.stat().st_dev == output.stat().st_dev
  required = (2 * size_gib + 12 if same_disk else size_gib + 12) * gib
  if shutil.disk_usage(parent).free < required:
    raise ValueError(f"workspace needs at least {required // gib} GiB free")
  if not same_disk and shutil.disk_usage(output).free < (size_gib + 1) * gib:
    raise ValueError(f"output filesystem needs at least {size_gib + 1} GiB free")
  nodes = os.statvfs(parent)
  # Btrfs reports zero for an unbounded inode pool.
  if (nodes.f_files == 0 and fstype != "btrfs") or (nodes.f_files and nodes.f_favail < 50000):
    raise ValueError("workspace needs at least 50000 free inodes")
  work = Path(tempfile.mkdtemp(prefix="omarchy-rpi4-", dir=parent))
  token = secrets.token_hex(32)
  (work / ".omarchy-image-workspace").write_text(json.dumps({"token": token, "uid": os.getuid()}))
  print(work)
  print(token)


def remove(value, token):
  work = plain_path(value)
  sentinel = work / ".omarchy-image-workspace"
  if not work.name.startswith("omarchy-rpi4-") or not work.is_dir() or sentinel.is_symlink():
    raise ValueError("refusing cleanup of an unowned workspace")
  state = json.loads(sentinel.read_text())
  if (work.stat().st_uid != os.getuid() or sentinel.stat().st_uid != os.getuid()
      or state != {"token": token, "uid": os.getuid()}):
    raise ValueError("workspace ownership sentinel does not match this invocation")
  # A failed/lazy unmount must never turn cleanup into recursive filesystem
  # deletion. Inspect all mounts under the child, including bind mounts.
  if Path("/proc/self/mountinfo").exists():
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
      mount = line.split()[4]
      for escaped, plain in (("\\040", " "), ("\\011", "\t"), ("\\012", "\n"), ("\\134", "\\")):
        mount = mount.replace(escaped, plain)
      if Path(mount) == work or work in Path(mount).parents:
        raise ValueError("workspace still contains a mounted filesystem; keeping it for recovery")
  shutil.rmtree(work)


if __name__ == "__main__":
  try:
    if len(sys.argv) == 6 and sys.argv[1] == "create":
      create(*sys.argv[2:5], int(sys.argv[5]))
    elif len(sys.argv) == 4 and sys.argv[1] == "remove":
      remove(*sys.argv[2:])
    else:
      raise ValueError("usage: workspace.py create PARENT REPO OUTPUT SIZE_GIB | remove CHILD TOKEN")
  except (OSError, ValueError, subprocess.CalledProcessError) as error:
    raise SystemExit(f"Error: {error}")
