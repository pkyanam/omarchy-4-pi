# Pi 4 optimization discovery — findings for a separate implementer

Discovery only. **Nothing here is fixed, patched, tuned or claimed as a win.** Every item below was measured or read from the running board on 2026-11-08 and is recorded so another agent can implement and prove it. The goal the items serve: match or beat Raspberry Pi OS on efficiency, with double-digit gains across the board where they are real.

Board: Pi 4 Model B Rev 1.5, `c03115`, MIDR `0x410fd083` (Cortex-A72 r0p3), 4GB, uncapped, booting `7.3.0-32.1-omarchy` at EL2 through PFTF/Limine/UKI. Storage is a USB SSD (LUKS2 + Btrfs). Overlays: `miniuart-bt`, `upstream-pi4`, `omarchy-pi4-mainline-dma`. Firmware config already sets `arm_boost=1`.

Baseline capture and trend log: `build/upstream-pi/stable-4.5/pi4-metrics.csv`, with `record-pi4-metrics.sh` to append a sample and `plot-pi4-metrics.py` to render it. `METRICS.md` beside them documents the columns, the sampling rules, and the measured noise floor, and is the file to read before recording a before/after pair. **Record a sample before a change and again after, under identical conditions**, and treat that trend as the comparison point rather than the numbers quoted here.

## Headline: the single biggest finding is that hardware AES is not available

`cryptsetup benchmark` on this board reports `aes-xts 512b ≈ 81 MiB/s`, `aes-xts 256b ≈ 104 MiB/s`. That is **software** AES throughput. Loading the accelerator fails outright:

```
modprobe aes_ce_blk → ERROR: could not insert 'aes_ce_blk': No such device
modprobe ghash_ce   → ERROR: could not insert 'ghash_ce': No such device
```

The kernel config is correct (`CONFIG_CRYPTO_AES_ARM64_CE_BLK=m`, `CRYPTO_GHASH_ARM64_CE=m`, and the `.ko` files really are in the package), and kernel cmdline carries no arm64 feature-mask argument. What is actually reported for the CPU is:

```
Features: fp asimd evtstrm crc32 cpuid
```

A Cortex-A72 has `aes`, `sha1`, `sha2`, `pmull` and LSE atomics; `crc32` is present, the rest are not. `dmesg` shows `CPU: All CPU(s) started at EL2`, so the firmware is running the kernel at the hypervisor level and the AArch64 identification registers seen by Linux are being mediated. **Do not assume this is a config error — the config is fine.** The investigating agent should determine whether PFTF/the EL2 stub masks `ID_AA64ISAR0_EL1` features, and if so whether the mask can be lifted in firmware (`config.txt`) or whether the kernel must be given the capability another way. Consequence if it is real and unfixable: every byte through the LUKS root and every zram page pays software AES cost.

This one is worth doing first because it touches all disk and swap I/O at once.

## Mitigations that cost and buy nothing on this board

Every Meltdown-class vulnerability reports **"Not affected"**, including `meltdown`, `retbleed`, `spec_store_bypass`, `mmio_stale_data`, `srbds`, `tsa`, `gather_data_sampling`:

```
meltdown     Not affected
retbleed     Not affected
spec_store_bypass  Not affected
spectre_v1   Mitigation: __user pointer sanitization
spectre_v2   Mitigation: Branch predictor hardening, BHB
```

Yet the kernel reports `CPU features: kernel page table isolation forced ON by KASLR` and `detected: Kernel page table isolation (KPTI)`. AArch64 A72 is not vulnerable to Meltdown, so KPTI buys nothing here and costs a page-table switch on every user/kernel transition. Measured on this board with KPTI on:

- `getpid`: **1.15–1.22 µs/call** (≈866k syscalls/s)
- `open+close /etc/hostname`: **12.6–14.5 µs/call**
- `fork`/`exec` of `/bin/true`: 0.666s for 300 (user 0.097s, sys 0.607s — almost entirely kernel-side)

The implementer should A/B `nopti`/`pti=off` (arm64 currently has **no runtime toggle**; it is boot-argument only, so each test needs a reboot) and decide whether to also drop KASLR, which is what forces PTI on here. Measure with the syscall microbenchmark in the probe script, not by feel. Do not blindly set `mitigations=off` — `spectre_v1`/`spectre_v2` mitigations are genuinely active and worth keeping; the target is specifically the page-table isolation that Meltdown alone justifies.

## Code generation: the toolchain is targeting the wrong CPU

`/etc/makepkg.conf` builds with `-march=armv8-a -O2`, and `OPTIONS` contains `!lto`. That is a generic ARMv8 baseline with no Cortex-A72 scheduling model.

Measured on the board with the same source, single core:

| Flags | integer loop | float loop |
| --- | --- | --- |
| `-march=armv8-a` (current) | 151 M it/s | 126 M it/s |
| `-mcpu=cortex-a72` | 152 M it/s | 130 M it/s |
| `-mcpu=cortex-a72 -O3` | **587 M it/s** | **251 M it/s** |
| `-mcpu=cortex-a72 -O3 -funroll-loops` | 583 M it/s | 252 M it/s |

Two separate findings, and the behavioural difference matters. **`-mcpu=cortex-a72` alone is worth only about 2–3%** — small, and this board's memory benchmarks showed no difference at all (433 vs 435 MB/s), because those are RAM-bound. **`-O3` is worth 3.9x on the integer loop and 2x on float.** So the tempting "add `-mcpu`" change is nearly worthless on its own; the loop-heavy win comes from `-O3`, which Arch's toolchain avoids on purpose for aarch64.

Caveats the implementer must respect: `-O3` is not free everywhere (code size up, some real-world code regresses), `!lto` removal interacts badly with `-O3` on constrained RAM, and this microbenchmark is a loop, which is the workload `-O3` flatters most. **Do not extrapolate 3.9x to the desktop.** The honest test is rebuilding a small set of real packages (`zstd`, `ffmpeg` or `llvm` if it fits in RAM, plus a browser) and measuring those.

Also unset: `CONFIG_LTO_NONE=y` for the kernel. Pi OS builds its kernel with LTO.

## Frequency scaling is using the wrong driver

`scaling_driver` reports **`cpufreq-dt`** — the generic Device Tree OPP driver — not `raspberrypi-cpufreq`. Both modules are loaded (`raspberrypi_cpufreq` is present), and there is no `opp-*` table under `/sys/firmware/devicetree/base/cpus/cpu@0/`, which is the generic driver's own source of truth. Linux's `raspberrypi-cpufreq` queries the firmware for the board's real maximum and is what the vendor path uses.

Consequences to verify, not assume: whether firmware-reported limits are honoured, whether `arm_boost=1` actually reaches 1.8 GHz under load, and whether the driver makes the governor's job easier. Measured here: `cpuinfo_max_freq` is 1800000, `scaling_cur_freq` settles at 1.3–1.6 GHz idle, and under a 20-second 4-core load the clock **held 1.8 GHz for 15 s then fell to 1.2 GHz at 20 s while temperature was only 51–54 °C**. That drop is not thermal — the only thermal trip point on this board is `110000` (110 °C) and `cooling_device0` is a PCIe link-speed device, not a CPU cooling device. So the fall to 1.2 GHz is governor/DVFS behaviour, not throttling, and an A72 running at 1.2 GHz under load is leaving performance on the table. `vcgencmd get_throttled` prints nothing at all and **`vcgencmd` is not installed** (`raspberrypi-4-support 1-1` provides the package; the binary is absent), so no firmware-side clock/voltage query is currently possible.

Related: `pi-tuning.md` documents clock profiles and a guard that "samples every 15 seconds" for undervoltage via native sensors. With `vcgencmd` absent, the implementer must confirm what those sensors actually are and whether `omarchy pi tune` can detect undervoltage at all on this image.

## Memory policy that is more aggressive than documented

`pi-tuning.md` states the inspected ALARM kernel enables LZO/LZO-RLE but not zstd, and that zram therefore uses the kernel default. **That is no longer true.** Live state:

```
/sys/block/zram0/comp_algorithm → lzo-rle lzo lz4 lz4hc [zstd] deflate 842
```

zstd is the active compressor, the package config agrees (`CONFIG_ZRAM_DEF_COMP_ZSTD=y`), and the device is 3924819968 bytes (≈3.9 GB) on a 3.7 GiB machine. `vm.swappiness=150`. `zswap.enabled=0` in the cmdline while zram is active.

That combination is defensible but untested: zstd compression on a board whose (apparent) lack of AES/extended crypto acceleration matters less here, but which has only four A72 cores, and with swappiness 150 pushing pages into a compressed-RAM device eagerly. This is exactly the "controlled test with actual builds and browser tabs" the older doc asked for and never got. Compare zstd vs lz4 vs lzo-rle at matched sizes on real workloads, and measure CPU cost alongside the memory saved — zram's cost is CPU, and this board's CPU headroom is the scarce resource.

## Memory configuration worth measuring

- `CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y`, `CONFIG_ARM64_4K_PAGES=y`. THP *always* is a known mixed blessing on 4GB ARM: it can amplify memory pressure and latency under fragmentation. The alternative (`madvise`) costs peak throughput on some workloads. Measure, do not assume.
- `CmaTotal: 65536 kB`, `CmaFree: 30816 kB`. The earlier hardware audit recorded nearly-full CMA usage at one instant and correctly refused to enlarge it. Unchanged here, still unproven either way.
- `CONFIG_LRU_GEN=y`, `CONFIG_LRU_GEN_ENABLED=y`. Relevant to the swappiness discussion above.

## Hardware video decode is entirely absent, and that is the media gap

```
ls /dev/video* /dev/media* → (none)
```

There is no V4L2 device of any kind on this board, so **nothing** decodes video in hardware. `ffmpeg -hwaccels` lists `vdpau cuda vaapi drm opencl vulkan amf` — all generic, none backed by a Pi codec. Config confirms the build-time cause found earlier: `BCM2835_VCHIQ` is not set, and mainline `bcm2835-codec`/`bcm2835-isp` depend on it. `VIDEO_BCM2835_UNICAM` is separately not set.

The implementer's decision is architectural, not a one-line config change: either enable the VCHIQ stack so the mainline firmware-backed codec exists, or accept software decode and stop advertising hardware decode. Do not copy Pi OS modules across ABI — the earlier audit is right about that. Camera is the cheap one: `VIDEO_BCM2835_UNICAM` needs no VCHIQ and is a single opt-in the moment a sensor exists.

## Interfaces, storage and platform limits

- **PCIe is at `Speed 5GT/s, Width x1`** (PCIe 2.0 x1). Pi 4 can be configured for Gen 3, and the VL805 USB controller sits behind this link — so the encrypted SSD's ceiling is set here. A Gen 2 or Gen 3 trial is a firmware-config change with real, measurable storage impact, and carries the usual signal-integrity caveat: not every board and cable sustains Gen 3. Measure with sequential and random I/O on the *actual* SSD, and be prepared to revert.
- `usbfs_memory_mb=16`, `autosuspend=2`. Both defaults; the USB memory cap limits large USB transfers and is worth testing if the SSD path shows stalls.
- Scheduler is `kyber` on the SSD and the SD card. `discard_max_bytes=0` was recorded earlier: the USB bridge does not advertise UNMAP, so `allow-discards` in the crypttab is inert. Not a bug, but do not attribute TRIM benefits here.
- `arm_boost=1` is already in the firmware config; the tuning docs are not proposing anything new there.

## What must be measured on a real 8GB board, not inferred

Everything above was measured on the 4GB model. These are the items where 8GB changes the answer and no inference is safe:

1. **zram sizing and swappiness.** Half-RAM and swappiness 150 were chosen for 4GB. On 8GB the compressed device doubles to ≈7.9 GB while the CPU cost per page is identical; the right size and the right compressor may differ, and the 4GB result must not simply be copied.
2. **Whether translator/hugepage behaviour differs.** THP-always on 8GB has far more room to fragment before it hurts, so a 4GB result may not transfer.
3. **CMA and `gpu_mem` floors.** Same absolute reservation on double the RAM is a smaller fraction; the "do not enlarge CMA" conclusion needs re-checking rather than repeating.
4. **Build parallelism.** `pi-tuning.md` caps makepkg at two jobs on 4GB. That cap is a RAM limit, not a core limit (the board has four), so 8GB should allow more — measure actual peak RSS during a real package build before raising it.
5. **Sustained thermal behaviour at the higher clock.** A 4GB board and an 8GB board of the same revision should behave alike, but the sustained-load clock drop documented above must be re-measured rather than assumed identical.

## Suggested order for the implementer

Ordered by expected gain per unit of risk, on the evidence above:

1. Establish the AES/EL2 question — it gates all storage and swap throughput and is currently unexplained. (Highest value, and the most likely place to find the double-digit I/O win.)
2. A/B page-table isolation, keeping the genuine Spectre mitigations. Syscall-heavy workloads are where the desktop and package management live.
3. Rebuild a small, real package set at `-O3` and at `-mcpu=cortex-a72` **separately**, and measure. Do not ship `-O3` globally on the strength of a loop benchmark.
4. Settle the CPUFreq driver (`cpufreq-dt` vs `raspberrypi-cpufreq`) and the unexplained 1.8→1.2 GHz drop under load.
5. Re-measure the zram compressor/size/swappiness combination that is now live but was never tested.
6. Decide the VCHIQ/media question explicitly, so the release either ships hardware decode or stops claiming it.
7. PCIe Gen 2/3 trial on the real SSD, with a revert plan.

## Boundaries this discovery respected

No file was modified outside this checkout. No package was installed, no service restarted, no display woken and no reboot was triggered for measurement (the one reboot in this session was the authorized kernel install). The only privileged reads were `dmesg`, `/etc/crypttab`, `cryptsetup benchmark`, `/sys/kernel/debug/clk`, and `modprobe` of three crypto modules — the two that failed left nothing loaded, so the board is in the state it was found in.

Measurements quoted here are single samples on a shared desktop with the compositor running, at 45–54 °C. They are good enough to rank hypotheses and not good enough to certify a release; the implementer must re-run `pi4-baseline-probe.sh` under repeatable conditions for any before/after claim.
