"""Encode and strictly validate Pi image provenance before issuing a receipt."""

import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit


UPSTREAM = "ac2690cd7be4f47e4a255f5e2e78d904d436b068"
BASE_SIGNER = "68B3537F39A313B3E574D06777193F152BDBE6A6"
RECIPE = "c7a1ef7f86cccab072fb11f22564862c03f50199"


def digest(path):
  hasher = hashlib.sha256()
  with path.open("rb") as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
      hasher.update(chunk)
  return hasher.hexdigest()


def tree_digest(source):
  hasher = hashlib.sha256()
  for path in sorted(source.rglob("*")):
    relative = path.relative_to(source)
    if relative.parts[0] in {".git", "build", "build-output-rpi4"} or path.name.startswith("._"):
      continue
    if path.is_symlink():
      payload = b"link:" + str(path.readlink()).encode()
    elif path.is_file():
      payload = b"exec:" + str(path.stat().st_mode & 0o111).encode() + b":" + bytes.fromhex(digest(path))
    else:
      continue
    hasher.update(str(relative).encode() + b"\0" + payload + b"\0")
  return hasher.hexdigest()


def unique_object(pairs):
  result = {}
  for name, value in pairs:
    if name in result:
      raise ValueError(f"duplicate JSON key: {name}")
    result[name] = value
  return result


def load(path):
  def invalid_constant(value):
    raise ValueError(f"invalid JSON constant: {value}")
  return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object, parse_constant=invalid_constant)


def require(condition, message):
  if not condition:
    raise ValueError(message)


def inventory(root):
  packages = []
  for path in sorted((root / "var/lib/pacman/local").glob("*/desc")):
    lines = path.read_text().splitlines()
    def field(name):
      return lines[lines.index(f"%{name}%") + 1]
    require(field("ARCH") in {"aarch64", "any"}, "installed package has a non-ARM architecture")
    packages.append({"name": field("NAME"), "version": field("VERSION")})
  packages.sort(key=lambda item: item["name"])
  require(bool(packages), "final package inventory is empty")
  require(len({item["name"] for item in packages}) == len(packages), "duplicate installed package")
  return packages


def mirrors(root):
  servers = []
  for name in ("etc/pacman.conf", "etc/pacman.d/mirrorlist"):
    for line in (root / name).read_text().splitlines():
      match = re.fullmatch(r"\s*Server\s*=\s*(\S+)\s*", line)
      if match and match[1] not in servers:
        servers.append(match[1])
  return servers


def validate(data, root=None, require_receipt=True):
  required = {"schema_version", "project", "platform", "built_at", "source_commit", "source_branch",
              "source_origin", "source_tracking_commit", "source_dirty", "source_tree_sha256", "build_kind",
              "upstream_release", "omarchy_pkgs_commit", "install_mode", "package_repository", "base_url",
              "base_sha256", "base_signing_key", "node_bundle", "packages"}
  require(isinstance(data, dict) and set(data) == required, "manifest fields do not match schema version 1")
  require(type(data["schema_version"]) is int and data["schema_version"] == 1, "unknown manifest schema")
  require(data["project"] == "omarchy-4-pi" and data["platform"] == "aarch64", "incorrect image project/platform")
  require(data["upstream_release"] == {"tag": "v4.5.0", "commit": UPSTREAM}, "incorrect upstream release lineage")
  require(data["omarchy_pkgs_commit"] == RECIPE, "image uses an unreviewed recipe commit")
  for field in ("source_commit", "source_tracking_commit"):
    value = data[field]
    require(field == "source_tracking_commit" and value is None or isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value), f"invalid {field}")
  for field in ("base_sha256", "source_tree_sha256"):
    require(isinstance(data[field], str) and re.fullmatch(r"[0-9a-f]{64}", data[field]), f"invalid {field}")
  require(type(data["source_dirty"]) is bool, "source_dirty must be a boolean")
  for field in ("source_branch", "source_origin", "built_at", "base_url"):
    require(isinstance(data[field], str) and bool(data[field]), f"invalid {field}")
  datetime.datetime.strptime(data["built_at"], "%Y-%m-%dT%H:%M:%SZ")
  require(data["base_signing_key"] == BASE_SIGNER, "unexpected base signer")
  require(data["install_mode"] in {"minimal", "full"}, "unknown install mode")
  require(data["build_kind"] in {"candidate", "release"}, "unknown build kind")
  if data["build_kind"] == "release":
    require(not data["source_dirty"] and data["source_branch"] == "main"
            and data["source_tracking_commit"] == data["source_commit"], "release source is unpublished or dirty")
  for url in [data["base_url"], *data["package_repository"]] if isinstance(data["package_repository"], list) else []:
    require(isinstance(url, str) and urlsplit(url).scheme in {"http", "https"} and bool(urlsplit(url).netloc)
            and not any(c.isspace() or ord(c) < 32 for c in url), "invalid source/repository URL")
  require(isinstance(data["package_repository"], list) and bool(data["package_repository"])
          and len(set(data["package_repository"])) == len(data["package_repository"]), "package_repository must be a nonempty mirror array")
  node = data["node_bundle"]
  require(isinstance(node, dict) and set(node) == {"filename", "sha256"}, "invalid Node bundle metadata")
  require(isinstance(node["filename"], str) and re.fullmatch(r"node-v[0-9]+(?:\.[0-9]+)*-linux-arm64\.tar\.gz", node["filename"]), "invalid ARM64 Node filename")
  require(isinstance(node["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", node["sha256"]), "invalid Node digest")
  packages = data["packages"]
  require(isinstance(packages, list) and bool(packages), "package inventory must be nonempty")
  for item in packages:
    require(isinstance(item, dict) and set(item) == {"name", "version"} and all(isinstance(v, str) and v and not any(c.isspace() for c in v) for v in item.values()), "invalid package record")
  require(len({p["name"] for p in packages}) == len(packages), "duplicate manifest package")
  if root is not None:
    require(packages == inventory(root), "build manifest records every installed package and exact version")
    require(data["package_repository"] == mirrors(root), "manifest mirrors differ from installed configuration")
    bundles = list((root / "var/lib/omarchy/provisioning/packages").glob("node-v*-linux-*.tar.gz"))
    require(len(bundles) == 1 and bundles[0].name == node["filename"] and digest(bundles[0]) == node["sha256"], "ARM64 Node.js bundle matches build provenance")
    source = root / "opt/omarchy-4-pi"
    require(tree_digest(source) == data["source_tree_sha256"], "source working snapshot differs from provenance")
    def git(*args):
      return subprocess.check_output(["git", "-C", str(source), *args], text=True, stderr=subprocess.DEVNULL).strip()
    require(git("rev-parse", "HEAD") == data["source_commit"], "source checkout HEAD differs from provenance")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    require(("detached" if branch == "HEAD" else branch) == data["source_branch"], "source checkout branch differs from provenance")
    require(git("remote", "get-url", "origin") == data["source_origin"], "source origin differs from provenance")
    try:
      tracking = git("rev-parse", "--verify", f"refs/remotes/origin/{branch}")
    except subprocess.CalledProcessError:
      tracking = None
    require(tracking == data["source_tracking_commit"], "source remote ref differs from provenance")
    if not data["source_dirty"]:
      require(not git("status", "--porcelain"), "clean-source claim differs from the installed checkout")
    require((source / "image/omarchy-pkgs.commit").read_text().strip() == data["omarchy_pkgs_commit"], "packaged recipe pin differs from provenance")
    receipt = root / "var/lib/omarchy/rpi4-source-commit"
    if data["source_dirty"]:
      require(not receipt.exists(), "dirty image must not carry a clean installed-core receipt")
    elif require_receipt:
      require(receipt.is_file() and receipt.read_text().strip() == data["source_commit"], "installed-core receipt differs from manifest")


def write(root, provenance, base_url, base_sha, mode):
  source = root / "opt/omarchy-4-pi"
  packages = inventory(root)
  bundles = list((root / "var/lib/omarchy/provisioning/packages").glob("node-v*-linux-*.tar.gz"))
  require(len(bundles) == 1, "exactly one offline ARM64 Node bundle is required")
  data = {
    "schema_version": 1, "project": "omarchy-4-pi", "platform": "aarch64",
    "built_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    **load(provenance), "upstream_release": {"tag": "v4.5.0", "commit": UPSTREAM},
    "omarchy_pkgs_commit": (source / "build-output-rpi4/omarchy-pkgs.commit").read_text().strip(),
    "install_mode": mode, "package_repository": mirrors(root), "base_url": base_url,
    "base_sha256": base_sha, "base_signing_key": BASE_SIGNER,
    "node_bundle": {"filename": bundles[0].name, "sha256": digest(bundles[0])}, "packages": packages,
  }
  validate(data, root, require_receipt=False)
  target = root / "usr/share/omarchy-rpi4/build-manifest.json"
  target.parent.mkdir(parents=True, exist_ok=True)
  temporary = target.with_suffix(".json.tmp")
  temporary.write_text(json.dumps(data, indent=2, ensure_ascii=True) + "\n")
  validate(load(temporary), root, require_receipt=False)
  temporary.replace(target)
  # Only parsed, inventory-checked, clean source can establish this receipt.
  if not data["source_dirty"]:
    receipt = root / "var/lib/omarchy/rpi4-source-commit"
    receipt.parent.mkdir(parents=True, exist_ok=True)
    receipt.write_text(data["source_commit"] + "\n")


if __name__ == "__main__":
  try:
    if sys.argv[1:2] == ["write"] and len(sys.argv) == 7:
      write(Path(sys.argv[2]), Path(sys.argv[3]), *sys.argv[4:])
    elif sys.argv[1:2] == ["validate"] and len(sys.argv) in {3, 4}:
      validate(load(Path(sys.argv[2])), Path(sys.argv[3]) if len(sys.argv) == 4 else None)
    else:
      raise ValueError("usage: rpi4-manifest.py write ROOT PROVENANCE BASE_URL BASE_SHA MODE | validate MANIFEST [ROOT]")
  except (OSError, ValueError, KeyError, TypeError, IndexError, subprocess.CalledProcessError) as error:
    raise SystemExit(f"Invalid Pi image manifest: {error}")
