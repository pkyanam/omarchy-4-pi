"""Rebase copied file catalogs and validate their unchanged image hashes."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse


def main():
  assets = Path(sys.argv[1]).resolve(strict=True)
  validator = Path(__file__).with_name("validate-imager-catalog.sh")
  catalogs = sorted(assets.glob("*.os-list.json")) + [assets / "os-list.json"]
  for path in catalogs:
    if path.is_symlink() or not path.is_file():
      raise ValueError(f"Missing or unsafe copied catalog: {path}")
    catalog = json.loads(path.read_text())
    for entry in catalog["os_list"]:
      url = urlparse(entry["url"])
      if url.scheme == "file":
        if url.netloc not in {"", "localhost"} or not url.path.startswith("/"):
          raise ValueError(f"Unsafe local image URL in {path}")
        entry["url"] = (assets / Path(unquote(url.path)).name).as_uri()
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=assets)
    try:
      with os.fdopen(descriptor, "w") as stream:
        json.dump(catalog, stream, indent=2)
        stream.write("\n")
      # This checks asset existence, size and digest on the host after copy.
      # Never recompute catalog hashes from potentially damaged copied bytes.
      subprocess.run(["bash", str(validator), temporary, str(assets)], check=True)
      os.chmod(temporary, 0o644)
      os.replace(temporary, path)
    finally:
      Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
  try:
    main()
  except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
    sys.exit(f"Cannot relocate copied Imager catalogs: {error}")
