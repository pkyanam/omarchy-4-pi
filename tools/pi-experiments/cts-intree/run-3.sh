#!/bin/bash
set -euo pipefail
exec > /candidate/logs/build.log 2>&1
trap 'status=$?; for f in memory.peak memory.events cpu.stat; do cat /sys/fs/cgroup/$f > /candidate/logs/$f; done; echo "EXIT=$status"; exit "$status"' EXIT
export TMPDIR=/work/tmp
cd /work/linux-7.3
export KCFLAGS=-gz=zstd KAFLAGS=-gz=zstd LDFLAGS_MODULE=--compress-debug-sections=zstd
export MAKEFLAGS=-j1 KBUILD_BUILD_USER=linux-omarchy KBUILD_BUILD_HOST=omarchy KBUILD_EXTMOD=
module=drivers/tty/serial/8250/8250_bcm2835aux
[[ $(sha256sum "$module.c" | cut -d' ' -f1) == "36cd6b9a527c56d683f7694ada656dba869028d3e1f998bde73b0229c81f3e18" ]]
make -j1 V=1 "$module.o"
make --no-print-directory -j1 V=1 -f Makefile -f /candidate/stage.mk stage-mod
printf '%s.o\n' "$module" > modules.order
# Supported real MODPOST CLI. -i reads complete archived exports; absence of -e
# follows actual in-tree compilation. No dummy vmlinux object or metadata patch.
scripts/mod/modpost -M -m -x -E -i /work/evidence/authenticated.symvers -T modules.order -o /work/evidence/baseline.symvers
make --no-print-directory -j1 V=1 -f Makefile -f /candidate/stage.mk stage-final
cp "$module.ko" /work/evidence/baseline.ko
cp "$module.mod.c" /candidate/logs/baseline.mod.c
cp "$(dirname "$module")/.8250_bcm2835aux.o.cmd" /candidate/logs/baseline.o.cmd
cp "$(dirname "$module")/.8250_bcm2835aux.ko.cmd" /candidate/logs/baseline.ko.cmd
python /candidate/check.py baseline
# Baseline must qualify before touching patched source.
patch --batch --fuzz=0 -p1 < /candidate/cts.patch
[[ $(sha256sum "$module.c" | cut -d' ' -f1) == "2ae07906f5415ceec9e4cac92a0d2f503e3e28150f0f3cdf8115087b34df6fb1" ]]
make -j1 V=1 "$module.o"
make --no-print-directory -j1 V=1 -f Makefile -f /candidate/stage.mk stage-mod
scripts/mod/modpost -M -m -x -E -i /work/evidence/authenticated.symvers -T modules.order -o /work/evidence/patched.symvers
make --no-print-directory -j1 V=1 -f Makefile -f /candidate/stage.mk stage-final
cp "$module.ko" /work/evidence/patched.ko
cp "$module.mod.c" /candidate/logs/patched.mod.c
cp "$(dirname "$module")/.8250_bcm2835aux.o.cmd" /candidate/logs/patched.o.cmd
python /candidate/check.py patched
