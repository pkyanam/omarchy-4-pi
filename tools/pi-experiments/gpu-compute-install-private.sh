#!/bin/bash
set -euo pipefail
exec > /evidence/dependency-install.log 2>&1
pacman -Q > /evidence/packages-before.txt
pacman -T glibc libstdc++ sh
# Check versioned ABI requirements against the existing providers before install.
python3 - <<'PY'
from pathlib import Path
import re
import subprocess
providers = ['/usr/lib/libc.so.6', '/usr/lib/libm.so.6', '/usr/lib/libstdc++.so.6', '/usr/lib/libgcc_s.so.1']
def versions(path):
  text = subprocess.check_output(['readelf', '--version-info', str(path)], text=True)
  return set(re.findall(r'\b(?:GLIBC|GLIBCXX|CXXABI|GCC)_[0-9.]+', text))
available = set().union(*(versions(p) for p in providers))
for name, path in [('glslang','usr/bin/glslang'), ('spirv-tools','usr/bin/spirv-val'), ('vulkan-icd-loader','usr/lib/libvulkan.so.1')]:
  binary = Path('/evidence/extracted') / name / path
  needed = versions(binary)
  missing = needed - available
  print(binary, 'required:', sorted(needed), 'missing:', sorted(missing), flush=True)
  if missing:
    raise SystemExit('existing libc/C++ ABI incompatible; stop without upgrade')
PY
pacman -U --noconfirm /evidence/packages/*.pkg.tar.xz
pacman -Q > /evidence/packages-after.txt
diff -u /evidence/packages-before.txt /evidence/packages-after.txt || [[ $? == 1 ]]
ldd -r /usr/bin/glslang /usr/bin/spirv-val /usr/lib/libvulkan.so.1
sha256sum /evidence/packages/* > /evidence/package-sha256.txt
