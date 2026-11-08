#!/bin/bash
set -euo pipefail
trap 'status=$?; for f in memory.peak memory.events cpu.stat; do cat /sys/fs/cgroup/$f > /candidate/logs/build-$f; done; echo EXIT=$status; exit "$status"' EXIT
mkdir -p /work/tmp /work/output /work/downloads
python /candidate/generate.py
cp /etc/makepkg.conf /work/makepkg.conf
printf '%s\n' 'MAKEFLAGS="-j1"' 'COMPRESSZST=(zstd -c -z -q --threads=1 -)' >> /work/makepkg.conf
export TMPDIR=/work/tmp
python /candidate/requalify.py
mkdir -p /work/source-verification /work/gnupg
chmod 700 /work/gnupg
cp -r /inputs/stable-4.5/cts-kernel-candidate/kernel/. /work/source-verification/
for f in /cache/downloads/*; do ln -sf "$f" /work/downloads/; done
ln -sf /inputs/linux-7.3.tar.xz /work/downloads/linux-7.3.tar.xz.full
chown -R builder:builder /work/source-verification /work/downloads /work/tmp /work/output /work/gnupg
runuser -u builder -- /bin/bash -s <<'VERIFY'
set -euo pipefail
cd /work/source-verification
export GNUPGHOME=/work/gnupg SRCDEST=/work/downloads
mkdir -p -m700 "$GNUPGHOME"
printf '%s\n' no-auto-key-retrieve 'auto-key-locate clear' > "$GNUPGHOME/gpg.conf"
for key in keys/pgp/*.asc; do gpg --batch --import "$key"; done
makepkg --config /work/makepkg.conf --verifysource --noconfirm
VERIFY
for name in linux-omarchy linux-omarchy-headers linux-omarchy-nvidia-open firmware; do
  cp -a "/work/recipes/$name" "/work/$name"
  if [[ $name != "firmware" ]]; then
    rm "/work/$name/base.pkg.tar.zst"
    ln -s "/inputs/stable-4.5/kernel-reviewed/packages/$name-7.3-32.1-aarch64.pkg.tar.zst" "/work/$name/base.pkg.tar.zst"
  fi
  if [[ $name == "linux-omarchy" ]]; then
    rm /work/linux-omarchy/patched.ko.zst
    ln -s /inputs/stable-4.5/cts-intree-candidate/modules/patched.ko.zst /work/linux-omarchy/patched.ko.zst
  fi
  chown -R -h builder:builder "/work/$name"
  runuser -u builder -- /bin/bash -s -- "$name" <<'BUILD'
set -euo pipefail
cd "/work/$1"
export PKGDEST=/work/output MAKEFLAGS=-j1 SOURCE_DATE_EPOCH=1794168000
export GNUPGHOME=/work/gnupg
makepkg --config /work/makepkg.conf --printsrcinfo
makepkg --config /work/makepkg.conf --verifysource --noconfirm
makepkg --config /work/makepkg.conf --noconfirm
BUILD
  if [[ $name != "firmware" ]]; then
    python /candidate/compare.py "$name" "/work/output/$name-7.3-32.11-aarch64.pkg.tar.zst"
    # Retire only this lane's reproducible staging after the exhaustive receipt.
    rm -rf "/work/$name/pkg" "/work/$name/src"
  fi
done
sha256sum /work/output/* > /candidate/logs/archives.sha256
