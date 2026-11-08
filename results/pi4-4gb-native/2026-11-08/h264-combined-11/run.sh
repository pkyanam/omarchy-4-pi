#!/bin/bash
set -euo pipefail
cd /evidence
python3 preflight.py
k=/work/headers/usr/lib/modules/7.3.0-32.1-omarchy/build
{
  gcc --version
  ld --version
  cat "$k/include/config/kernel.release"
  grep -E 'CONFIG_(MODVERSIONS|MODULES|MODULE_UNLOAD|DEBUG_INFO|DEBUG_INFO_BTF|GCC_VERSION|CC_VERSION_TEXT|RANDSTRUCT)' "$k/.config"
  cat /sys/fs/cgroup/{cpu.max,memory.max,memory.swap.max,memory.events,memory.peak}
  du -sk /work /evidence
} > environment.log
# Make's normal header prerequisites may write only the private Linux clone.
set +e
make -C "$k" M=/work/source -j1 modules >compile.log 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > compile.exit
cat /sys/fs/cgroup/{memory.events,memory.peak,memory.current,cpu.stat} > cgroup-after.log
python3 /evidence/audit.py /work/headers /evidence/headers-clone-after.json
python3 /evidence/audit.py /input/headers /evidence/headers-original-after.json
python3 /evidence/audit.py /work/source /evidence/artifacts.json
if (( rc == 0 )); then
  for f in /work/source/*.ko; do
    modinfo "$f"
    modprobe --show-modversions "$f"
    readelf -SW "$f"
  done > modules-abi.log 2>&1
fi
cp -a /work/source /evidence/source
 du -sk /work /evidence > storage-after.log
exit "$rc"
