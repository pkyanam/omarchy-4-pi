#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
export PYTHONDONTWRITEBYTECODE=1
python3 - "$ROOT" <<'PY'
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("workspace", Path(sys.argv[1]) / "image/workspace.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def check(condition, description):
  if not condition:
    raise SystemExit(f"not ok - {description}")
  print(f"ok - {description}")

with tempfile.TemporaryDirectory(prefix="rpi45-image-storage-") as temporary:
  top = Path(temporary).resolve()
  parent, repo, output = (top / name for name in ("caller", "repo", "output"))
  for path in (parent, repo, output):
    path.mkdir()
  unrelated = parent / "caller-data"
  unrelated.write_text("must survive all cleanups")
  def allocate():
    result = io.StringIO()
    with contextlib.redirect_stdout(result):
      m.create(str(parent), str(repo), str(output), 12)
    path, token = result.getvalue().splitlines()
    return Path(path), token
  # Disk usage/filesystem are external boundaries; path/sentinel checks and
  # actual creation/deletion run unchanged on this small fixture filesystem.
  with patch.object(m.subprocess, "check_output", return_value="ext4\n"), patch.object(m.shutil, "disk_usage", return_value=type("Disk", (), {"free": 80 * 1024**3})()), patch.object(m.os, "statvfs", return_value=type("Nodes", (), {"f_files": 100000, "f_favail": 90000})()):
    child, token = allocate()
    (child / "partial-download").write_bytes(b"partial")
    m.remove(str(child), token)
    check(not child.exists() and unrelated.read_text() == "must survive all cleanups", "normal/failed-build cleanup deletes only its owned child")
    child, token = allocate()
    try:
      m.remove(str(child), "wrong token")
    except ValueError:
      pass
    else:
      raise SystemExit("not ok - mismatched ownership token accepted")
    check(child.exists() and unrelated.exists(), "mismatched sentinel preserves workspace and caller data")
    sentinel = child / ".omarchy-image-workspace"
    saved = sentinel.read_text()
    sentinel.unlink()
    sentinel.symlink_to(unrelated)
    try:
      m.remove(str(child), token)
    except ValueError:
      pass
    else:
      raise SystemExit("not ok - symlinked sentinel accepted")
    sentinel.unlink()
    sentinel.write_text(saved)
    m.remove(str(child), token)
    link = top / "linked-caller"
    link.symlink_to(parent, target_is_directory=True)
    for hazard in (Path("/"), Path.home(), repo, repo / "child", repo.parent, output, output / "child", link):
      try:
        m.create(str(hazard), str(repo), str(output), 12)
      except ValueError:
        pass
      else:
        raise SystemExit(f"not ok - dangerous parent accepted: {hazard}")
    check(unrelated.exists(), "root/repository/output overlaps and symlink parents fail before deletion")
    with patch.object(m.os, "statvfs", return_value=type("Nodes", (), {"f_files": 100000, "f_favail": 1})()):
      try:
        allocate()
      except ValueError:
        pass
      else:
        raise SystemExit("not ok - exhausted fixed inode pool accepted")
    with patch.object(m.os, "statvfs", return_value=type("Nodes", (), {"f_files": 0, "f_favail": 0})()):
      try:
        allocate()
      except ValueError:
        pass
      else:
        raise SystemExit("not ok - unknown ext4 inode capacity accepted")
      with patch.object(m.subprocess, "check_output", return_value="btrfs\n"):
        child, token = allocate()
        m.remove(str(child), token)
    check(list(parent.iterdir()) == [unrelated], "inode checks refuse exhausted ext4 and allow btrfs dynamic capacity")
  with patch.object(m.subprocess, "check_output", return_value="tmpfs\n"):
    try:
      allocate()
    except ValueError:
      pass
    else:
      raise SystemExit("not ok - tmpfs workspace accepted")
  with patch.object(m.subprocess, "check_output", return_value="ext4\n"), patch.object(m.shutil, "disk_usage", return_value=type("Disk", (), {"free": 1024})()):
    try:
      allocate()
    except ValueError:
      pass
    else:
      raise SystemExit("not ok - insufficient storage accepted")
  check(list(parent.iterdir()) == [unrelated], "memory-backed/low-space preflights create no owned workspace")
PY

# Factory scrub is a real filesystem operation. Only gpgconf's chroot boundary
# is stubbed; it cannot operate on the host or provide the removal behavior.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
(
  source "$ROOT/image/build-rpi4-image.sh"
  root_mount="$test_tmp/root"
  mkdir -p "$root_mount/etc/pacman.d/gnupg/private-keys-v1.d" "$root_mount/var/lib/omarchy/image" "$root_mount/usr/share/pacman/keyrings"
  printf 'dummy fixture private material\n' >"$root_mount/etc/pacman.d/gnupg/private-keys-v1.d/fixture.key"
  printf 'public vendor trust\n' >"$root_mount/usr/share/pacman/keyrings/omarchy.gpg"
  printf 'install/hardware/raspberry-pi.sh\n' >"$root_mount/var/lib/omarchy/image/deferred-steps"
  chroot() { [[ $1 == "$root_mount" && $* == *gpgconf* ]]; }
  scrub_factory_keyring
  [[ ! -e $root_mount/etc/pacman.d/gnupg && -f $root_mount/var/lib/omarchy/image/pacman-keyring && -s $root_mount/usr/share/pacman/keyrings/omarchy.gpg ]]
) || fail "factory removes all private pacman identity and arms offline per-device initialization"
pass "factory removes all private pacman identity and arms offline per-device initialization"
