# Setup default work directory (and tries).
mkdir -p "$HOME/Work/tries"

# Pi images promise an offline Node runtime as well as the lazy default shims.
# Preload the installer-verified bundle into mise's install store, without
# selecting a version or writing the user's config. User pins and opt-out stay
# in force; ordinary user finalization needs only the offline shims in mise.sh.
if [[ ${OMARCHY_SETUP_CONTEXT:-runtime} == "provision-owner" ]] &&
  omarchy-hw-raspberry-pi && omarchy-hw-aarch64 && omarchy-mise-default-tools declares node; then
  python3 -I - "${OMARCHY_NODE_PACKAGE_DIR:-/var/lib/omarchy/provisioning/packages}" \
    "${OMARCHY_NODE_BUNDLE_MANIFEST:-/usr/share/omarchy-rpi4/build-manifest.json}" \
    "$HOME/.local/share/mise/installs/node" <<'PY'
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile
import tempfile


def valid_node(path):
  if path.is_symlink() or not path.is_file() or not os.access(path, os.X_OK):
    return False
  with path.open("rb") as executable:
    header = executable.read(20)
  return header[:6] == b"\x7fELF\x02\x01" and header[18:20] == b"\xb7\x00"


def valid_runtime(path):
  return valid_node(path / "bin/node") and all(
    (path / "bin" / command).is_file() for command in ("npm", "npx")
  )


try:
  packages, manifest, installs = map(Path, sys.argv[1:])
  bundles = list(packages.glob("node-v*-linux-arm64.tar.gz"))
  if len(bundles) != 1 or bundles[0].is_symlink() or not bundles[0].is_file():
    raise ValueError("exactly one regular ARM64 Node archive is required")
  bundle = bundles[0]
  match = re.fullmatch(r"node-v([0-9]+\.[0-9]+\.[0-9]+)-linux-arm64\.tar\.gz", bundle.name)
  if not match:
    raise ValueError("the ARM64 Node archive has an invalid version")
  # A standalone OEM installation has the verified download receipt but no
  # disk-image manifest. An existing image manifest is always authoritative;
  # malformed or mismatching image provenance must not trigger a fallback.
  if not manifest.exists():
    manifest = packages / "node-bundle.json"
  receipt = json.loads(manifest.read_text())["node_bundle"]
  expected = receipt["sha256"]
  if receipt["filename"] != bundle.name or not re.fullmatch(r"[0-9a-f]{64}", expected):
    raise ValueError("the Node archive is not identified by the image manifest")
  with bundle.open("rb") as archive:
    actual = hashlib.file_digest(archive, "sha256").hexdigest()
  if actual != expected:
    raise ValueError("the Node archive checksum does not match the image manifest")

  installs.mkdir(parents=True, exist_ok=True)
  target = installs / match[1]
  if target.exists() or target.is_symlink():
    if target.is_symlink() or not valid_runtime(target):
      raise ValueError("the existing Node install is incomplete; repair it before retrying")
    # Never replace a user's existing version or unpack again on setup retries.
    sys.exit(0)
  archive_root = bundle.name.removesuffix(".tar.gz")
  # Stage on the install filesystem. A failed unpack never leaves a partial
  # version for mise to select, and an interrupted attempt can retry safely.
  with tempfile.TemporaryDirectory(prefix=".omarchy-node-", dir=installs) as staging:
    with tarfile.open(bundle, "r:gz") as archive:
      for member in archive.getmembers():
        parts = PurePosixPath(member.name).parts
        if not parts or parts[0] != archive_root or ".." in parts:
          raise ValueError("the Node archive contains an unexpected path")
      archive.extractall(staging, filter="data")
    unpacked = Path(staging) / archive_root
    if not valid_runtime(unpacked):
      raise ValueError("the Node archive has no complete Linux ARM64 runtime")
    unpacked.rename(target)
  print("Verified offline Node runtime is available to mise's default declaration.")
except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
  print(f"Error: offline Node setup failed: {error}; owner setup remains pending.", file=sys.stderr)
  sys.exit(1)
PY
fi
