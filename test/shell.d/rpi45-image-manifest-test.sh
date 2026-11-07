#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
require_command git
export PYTHONDONTWRITEBYTECODE=1 GIT_CONFIG_NOSYSTEM=1

# Real JSON, pacman records, file hashes, receipt handling, and a tiny Git object
# store. Git plumbing writes only this temporary fixture, never this checkout.
python3 - "$ROOT" <<'PY'
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("manifest", repo / "image/rpi4-manifest.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def check(condition, description):
  if not condition:
    raise SystemExit(f"not ok - {description}")
  print(f"ok - {description}")

with tempfile.TemporaryDirectory(prefix="rpi45-image-manifest-") as temporary:
  root = Path(temporary) / "root"
  source = root / "opt/omarchy-4-pi"
  source.mkdir(parents=True)
  def git(*args, input=None):
    return subprocess.check_output(["git", "-C", str(source), *args], input=input, text=True, stderr=subprocess.DEVNULL).strip()
  git("init", "--quiet", "-b", "codex/omarchy-4.5-pi4")
  git("remote", "add", "origin", "https://github.com/pkyanam/omarchy-4-pi.git")
  (source / "image").mkdir()
  (source / "image/omarchy-pkgs.commit").write_text(m.RECIPE + "\n")
  (source / ".gitignore").write_text("/build-output-rpi4/\n")
  pin_blob = git("hash-object", "-w", "--stdin", input=(source / "image/omarchy-pkgs.commit").read_text())
  ignore_blob = git("hash-object", "-w", "--stdin", input=(source / ".gitignore").read_text())
  image_tree = git("mktree", input=f"100644 blob {pin_blob}\tomarchy-pkgs.commit\n")
  tree = git("mktree", input=f"100644 blob {ignore_blob}\t.gitignore\n040000 tree {image_tree}\timage\n")
  commit = git("-c", "user.name=Image fixture", "-c", "user.email=fixture@example.invalid", "commit-tree", tree, input="Tiny image source fixture\n")
  git("update-ref", "refs/heads/codex/omarchy-4.5-pi4", commit)
  git("read-tree", commit)
  # The real Mac wrapper must transfer an unpublished local commit through a
  # shallow object store; no remote service, container, or checkout is used.
  transfer = subprocess.check_output([os.environ.get("BASH", "/bin/bash"), "-c", '''
source "$1/image/build-rpi4-image-macos.sh"
prepare_source_transfer "$2" "$3" ""
printf '%s\\n' "$transfer_dir"
''', "fixture", str(repo), str(source), commit], text=True, env={**os.environ, "TMPDIR": temporary}).strip()
  destination = Path(temporary) / "copied-git"
  subprocess.run(["git", "init", "--quiet", "--bare", str(destination)], check=True)
  subprocess.run(["git", "-C", str(destination), "fetch", "--quiet", "--depth", "1", str(Path(transfer) / "source-git"), commit], check=True)
  fetched = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "FETCH_HEAD"], text=True).strip()
  check(fetched == commit, "Mac source transfer carries an unpublished exact commit without fetching a public branch")
  (source / "build-output-rpi4").mkdir()
  (source / "build-output-rpi4/omarchy-pkgs.commit").write_text(m.RECIPE + "\n")
  for name in ("omarchy", "omarchy-settings"):
    desc = root / f"var/lib/pacman/local/{name}-4.5.0.pi4.1-1/desc"
    desc.parent.mkdir(parents=True)
    desc.write_text(f"%NAME%\n{name}\n\n%VERSION%\n4.5.0.pi4.1-1\n\n%ARCH%\naarch64\n")
  (root / "etc/pacman.d").mkdir(parents=True)
  urls = ['https://first.invalid/$arch/$repo', 'https://second.invalid/path?quoted="value"&slash=\\', 'https://third.invalid/$arch/$repo']
  (root / "etc/pacman.conf").write_text("[options]\nArchitecture = aarch64\n")
  (root / "etc/pacman.d/mirrorlist").write_text("\n".join(f"Server = {url}" for url in urls) + "\n")
  bundle = root / "var/lib/omarchy/provisioning/packages/node-v26.1.0-linux-arm64.tar.gz"
  bundle.parent.mkdir(parents=True)
  bundle.write_bytes(b"checksum-covered offline bundle fixture")
  provenance = Path(temporary) / "source.json"
  data = {"source_commit": commit, "source_branch": "codex/omarchy-4.5-pi4", "source_origin": git("remote", "get-url", "origin"), "source_tracking_commit": None, "source_dirty": False, "source_tree_sha256": m.tree_digest(source), "build_kind": "candidate"}
  provenance.write_text(json.dumps(data))
  m.write(root, provenance, 'https://base.invalid/quote"slash\\.tar.gz', "a" * 64, "minimal")
  target = root / "usr/share/omarchy-rpi4/build-manifest.json"
  manifest = m.load(target)
  m.validate(manifest, root)
  check(manifest["package_repository"] == urls and manifest["packages"] == m.inventory(root), "encoder preserves three mirrors, escaping, and exact installed inventory")
  receipt = root / "var/lib/omarchy/rpi4-source-commit"
  check(receipt.read_text().strip() == commit, "validated clean candidate gets an exact installed-source receipt without a fabricated remote ref")
  for field, replacement in (("source_dirty", "false"), ("omarchy_pkgs_commit", "0" * 40), ("package_repository", "one string"), ("packages", manifest["packages"][:1])):
    bad = copy.deepcopy(manifest)
    bad[field] = replacement
    try:
      m.validate(bad, root)
    except (ValueError, TypeError):
      pass
    else:
      raise SystemExit(f"not ok - rejected invalid {field}")
  check(True, "strict schema rejects wrong types, unreviewed recipes, and incomplete inventory")
  for bad in ('{"source_commit": "first", "source_commit": "second"}', '{"mirror":"literal\nnewline"}', '{"value":NaN}'):
    invalid = Path(temporary) / "invalid.json"
    invalid.write_text(bad)
    try:
      m.load(invalid)
    except ValueError:
      pass
    else:
      raise SystemExit("not ok - malformed JSON was accepted")
  check(True, "strict parser rejects duplicate keys, literal newlines, and non-JSON constants")
  bundle.write_bytes(b"tampered")
  try:
    m.validate(manifest, root)
  except ValueError:
    pass
  else:
    raise SystemExit("not ok - Node tampering was accepted")
  check(True, "Node digest is checked against real staged bytes")
  receipt.unlink()
  data["source_commit"] = "invalid"
  provenance.write_text(json.dumps(data))
  try:
    m.write(root, provenance, "https://base.invalid/rootfs", "a" * 64, "minimal")
  except ValueError:
    pass
  else:
    raise SystemExit("not ok - invalid provenance received a receipt")
  check(not receipt.exists(), "manifest failure cannot issue an installed-core receipt")
  data["source_commit"] = commit
  data["source_dirty"] = True
  (source / "working-edit").write_text("uncommitted candidate change\n")
  data["source_tree_sha256"] = m.tree_digest(source)
  provenance.write_text(json.dumps(data))
  m.write(root, provenance, "https://base.invalid/rootfs", "a" * 64, "minimal")
  m.validate(m.load(target), root)
  check(not receipt.exists() and m.load(target)["source_dirty"] is True, "dirty candidate records its working snapshot and cannot claim a clean receipt")
  (source / "working-edit").write_text("changed after snapshot\n")
  try:
    m.validate(m.load(target), root)
  except ValueError:
    pass
  else:
    raise SystemExit("not ok - mutated source snapshot accepted")
  check(True, "source snapshot changes after assembly are detected")
PY
