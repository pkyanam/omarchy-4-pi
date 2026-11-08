#!/bin/bash
set -euo pipefail
mkdir /work
cp -a /candidate/kernel /work/kernel
mkdir /work/downloads
cp /cache/downloads/* /work/downloads/
chown -R builder:builder /work
runuser -u builder -- /bin/bash -s <<'VERIFY'
set -euo pipefail
cd /work/kernel
export GNUPGHOME=/work/gnupg
mkdir -m700 "$GNUPGHOME"
printf '%s\n' 'no-auto-key-retrieve' 'auto-key-locate clear' >"$GNUPGHOME/gpg.conf"
for key in keys/pgp/*.asc; do gpg --batch --import "$key"; done
export SRCDEST=/work/downloads
makepkg --verifysource --noconfirm
VERIFY
for item in memory.peak memory.events cpu.stat; do cat "/sys/fs/cgroup/$item" >"/evidence/$item"; done
