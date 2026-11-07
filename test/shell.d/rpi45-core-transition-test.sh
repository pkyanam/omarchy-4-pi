#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"
require_command python3
require_command pacman
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# Ask the actual recipe adaptation for the installed core's dependencies.
cat >"$test_tmp/PKGBUILD" <<'RECIPE'
pkgver=4.5.0
pkgrel=3
depends=('hyprland' 'quickshell' "omarchy-settings=${pkgver}")
RECIPE
OMARCHY_PACKAGE_OUTPUT="$test_tmp/output" bash -e -c '
  source "$1/build-packages-rpi4.sh"
  adapt_recipe omarchy "$2/PKGBUILD"
  source "$2/PKGBUILD"
  printf "%s\n" "${depends[@]}" >"$2/dependencies"
' bash "$ROOT" "$test_tmp"

# The real libalpm prepare step reads tiny isolated local/sync databases. No
# package downloads, installation, root privilege, or system database access.
python3 -I - "$test_tmp" <<'PY'
import io
from pathlib import Path
import subprocess
import sys
import tarfile

root = Path(sys.argv[1])
db = root / "db"
(db / "local").mkdir(parents=True)
(db / "local/ALPM_DB_VERSION").write_text("9\n")
(db / "sync").mkdir()
(root / "target").mkdir()
(root / "cache").mkdir()
(root / "hooks").mkdir()
(root / "pacman.conf").write_text("[options]\nArchitecture = aarch64\nSigLevel = Never\nIgnorePkg = omarchy omarchy-settings\n[fixture]\nServer = https://packages.invalid/$arch\n")

def record(name, version, dependencies=(), remote=False):
  fields = {"NAME": [name], "VERSION": [version], "ARCH": ["any"], "DESC": ["isolated dependency fixture"]}
  if dependencies:
    fields["DEPENDS"] = list(dependencies)
  if remote:
    fields.update(FILENAME=[f"{name}-{version}-any.pkg.tar.zst"], CSIZE=["1"], ISIZE=["1"], SHA256SUM=["0" * 64])
  return "".join(f"%{key}%\n" + "\n".join(values) + "\n\n" for key, values in fields.items())

installed = {"hyprland": "0.56.2-7", "quickshell": "0.3.2.r7.g2b4501a-1", "omarchy-hyprland-titlebars": "0.2.2-2", "mise-bin": "2026.11.2-1", "omarchy-settings": "4.5.0.pi4.1-1"}
for name, version in installed.items():
  directory = db / "local" / f"{name}-{version}"
  directory.mkdir()
  (directory / "desc").write_text(record(name, version))
  (directory / "files").write_text("%FILES%\n\n")
core = db / "local/omarchy-4.5.0.pi4.1-1"
core.mkdir()
(core / "files").write_text("%FILES%\n\n")
with tarfile.open(db / "sync/fixture.db", "w:gz") as archive:
  data = record("hyprland", "0.56.2-8", remote=True).encode()
  item = tarfile.TarInfo("hyprland-0.56.2-8/desc")
  item.size = len(data)
  archive.addfile(item, io.BytesIO(data))

def prepare(dependencies):
  (core / "desc").write_text(record("omarchy", "4.5.0.pi4.1-1", dependencies))
  return subprocess.run(["pacman", "--config", str(root / "pacman.conf"), "--root", str(root / "target"), "--dbpath", str(db), "--cachedir", str(root / "cache"), "--hookdir", str(root / "hooks"), "--logfile", str(root / "pacman.log"), "-Sp", "--noconfirm", "--print-format", "%n %v", "fixture/hyprland=0.56.2-8"], text=True, capture_output=True)

blocked = prepare(["hyprland=0.56.2-7"])
diagnostic = blocked.stdout + blocked.stderr
assert blocked.returncode != 0 and "breaks dependency" in diagnostic and "hyprland=0.56.2-7" in diagnostic, blocked
allowed = prepare((root / "dependencies").read_text().splitlines())
assert allowed.returncode == 0, allowed.stderr
assert "hyprland 0.56.2-8" in allowed.stdout, allowed.stdout
assert (db / "local/hyprland-0.56.2-7/desc").exists(), "print-only solver changed installed state"
PY
pass "real libalpm rejects the former reverse pin and permits a reviewed runtime advance before core replacement"
