#!/bin/bash
set -euo pipefail
trap 'status=$?; for f in memory.peak memory.events cpu.stat; do cat /sys/fs/cgroup/$f > /evidence/$f; done; exit "$status"' EXIT
mkdir -p /tmp/companion /tmp/output
cp -a /candidate/firmware/. /tmp/companion/
pacman -Q > /evidence/installed-packages.txt
pacman -T base-devel dtc
if pacman -T 'linux-omarchy=7.3-32.2' raspberrypi-4-support > /evidence/absent-runtime.txt; then
  echo 'Unexpected runtime packages installed' >&2
  exit 1
fi
CTS_SOURCE_ONLY=0 bash /candidate/kernel/offline-inputs.sh /candidate/firmware /tmp
chown -R builder:builder /tmp/companion /tmp/output
runuser -u builder -- /bin/bash -c 'printf "%s\n" '"'"'MAKEFLAGS="-j1"'"'"' '"'"'COMPRESSZST=(zstd -c -z -q --threads=1 -)'"'"' > /home/builder/.makepkg.conf'
runuser -u builder -- /bin/bash -c 'set -euo pipefail; cd /tmp/companion; export PKGDEST=/tmp/output MAKEFLAGS=-j1 SOURCE_DATE_EPOCH=1794113568; makepkg --printsrcinfo; makepkg --verifysource --noconfirm; makepkg --noconfirm'
cp -a /tmp/companion /evidence/worktree
cp /tmp/output/* /evidence/
sha256sum /tmp/output/* > /evidence/archive.sha256
