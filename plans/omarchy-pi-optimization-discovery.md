# Pi 4 optimization discovery — findings for a separate implementer

Originally a discovery-only snapshot on November 8, now corrected during implementation. Measurements quoted below remain historical shared-session observations, not validated improvement claims. [Primary-source audit](omarchy-pi-primary-source-audit.md) records exact source/version evidence; [implementation progress](omarchy-pi-implementation-progress.md) records actual changes and acceptance gates. Raspberry Pi OS parity and double-digit gains remain unproven.

Board: Pi 4 Model B Rev 1.5, `c03115`, MIDR `0x410fd083` (Cortex-A72 r0p3), 4GB, uncapped, booting `7.3.0-32.1-omarchy` at EL2 through PFTF/Limine/UKI. Storage is a USB SSD (LUKS2 + Btrfs). Overlays: `miniuart-bt`, `upstream-pi4`, `omarchy-pi4-mainline-dma`. Firmware config already sets `arm_boost=1`.

Legacy baseline: the six rows in `build/upstream-pi/stable-4.5/pi4-metrics.csv` are preserved, with a tracked copy under `tools/pi-metrics/legacy/`. The old recorder's stdin/root bugs, unpersisted labels and probe semantic errors invalidate its use as an improvement curve. Use the versioned tools in `tools/pi-metrics/`, explicitly separating cohorts and unknowns. Never join v1 and v2 or merge 8GB/Pi 5 samples.

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

Correction: Cortex-A72 does not guarantee optional AES/SHA/PMULL or LSE. The EL2 entry message does not prove feature masking. Missing feature flags and rejected CE modules are consistent with capability gating; never force HWCAP bits. Investigate supported NEON/bitsliced software XTS selection and actual encrypted I/O separately. Ordinary zram compresses pages in RAM and does not encrypt each page because root uses LUKS. OpenSSL CBC is not dm-crypt XTS throughput. See the primary-source audit for exact driver checks.

## Mitigation cost with security preserved

Every Meltdown-class vulnerability reports **"Not affected"**, including `meltdown`, `retbleed`, `spec_store_bypass`, `mmio_stale_data`, `srbds`, `tsa`, `gather_data_sampling`:

```
meltdown     Not affected
retbleed     Not affected
spec_store_bypass  Not affected
spectre_v1   Mitigation: __user pointer sanitization
spectre_v2   Mitigation: Branch predictor hardening, BHB
```

Yet the kernel reports `CPU features: kernel page table isolation forced ON by KASLR` and `detected: Kernel page table isolation (KPTI)`. The exact arm64 source also uses KPTI to improve KASLR robustness, independently of its Meltdown-safe A72 classification. Keep that hardening enabled. Measured on this board with KPTI on:

- `getpid`: **1.15–1.22 µs/call** (≈866k syscalls/s)
- `open+close /etc/hostname`: **12.6–14.5 µs/call**
- `fork`/`exec` of `/bin/true`: 0.666s for 300 (user 0.097s, sys 0.607s — almost entirely kernel-side)

These Python-inclusive timings do not isolate bare syscall cost. Preserve KPTI/KASLR/Spectre posture while profiling real package/browser workloads and opportunities to batch operations. arm64 supports `kpti=0/1`; `nopti` and `pti=off` are x86 controls. Any explicitly justified mitigation experiment must document reduced KASLR hardening and restore the original posture; it is not a shipping optimization.

## Code generation: package-specific experiments needed

`/etc/makepkg.conf` builds with `-march=armv8-a -O2`, and `OPTIONS` contains `!lto`. Those are local build defaults, not evidence for the flags used in installed packages. Generic flags preserve the supported shared aarch64 ABI.

Measured on the board with the same source, single core:

| Flags | integer loop | float loop |
| --- | --- | --- |
| `-march=armv8-a` (current) | 151 M it/s | 126 M it/s |
| `-mcpu=cortex-a72` | 152 M it/s | 130 M it/s |
| `-mcpu=cortex-a72 -O3` | **587 M it/s** | **251 M it/s** |
| `-mcpu=cortex-a72 -O3 -funroll-loops` | 583 M it/s | 252 M it/s |

Two separate findings, and the behavioural difference matters. **`-mcpu=cortex-a72` alone is worth only about 2–3%** — small, and this board's memory benchmarks showed no difference at all (433 vs 435 MB/s), because those are RAM-bound. **`-O3` is worth 3.9x on the integer loop and 2x on float.** So the tempting "add `-mcpu`" change is nearly worthless on its own; the loop-heavy win comes from `-O3`, which Arch's toolchain avoids on purpose for aarch64.

Caveats the implementer must respect: `-O3` is not free everywhere (code size up, some real-world code regresses), `!lto` removal interacts badly with `-O3` on constrained RAM, and this microbenchmark is a loop, which is the workload `-O3` flatters most. **Do not extrapolate 3.9x to the desktop.** The honest test is rebuilding a small set of real packages (`zstd`, `ffmpeg` or `llvm` if it fits in RAM, plus a browser) and measuring those.

The resolved candidate has `CONFIG_LTO_NONE=y`; unknown or mismatched configs must not be reported as enabled LTO. A Pi OS LTO comparison needs a named matching release/config and representative workload.

## Frequency scaling: expected driver architecture, unresolved historical drop

Exact Linux 7.3 `raspberrypi-cpufreq` queries firmware clock limits, adds dynamic OPPs, and registers `cpufreq-dt`. That displayed name and absence of static DT OPP nodes are expected, not a driver defect. The historical requested-frequency drop from 1.8 to 1.2 GHz remains unexplained. A 110°C Linux thermal trip does not rule out independent firmware thermal/voltage throttling; `scaling_cur_freq` is not an independent silicon clock measurement.

The native raspberrypi-hwmon voltage alarm is present even though vcgencmd is absent. It does not expose the complete firmware throttle history; its polling also affects sticky flags. A reversible four-trial governor screening run found no repeatable benefit from performance, and restored schedutil. See `results/pi4-4gb-native/2026-11-08/` for raw results, contention/temperature limitations and unknown firmware clocks/energy. No governor default change is justified.

## Memory policy that is more aggressive than documented

`pi-tuning.md` states the inspected ALARM kernel enables LZO/LZO-RLE but not zstd, and that zram therefore uses the kernel default. **That is no longer true.** Live state:

```
/sys/block/zram0/comp_algorithm → lzo-rle lzo lz4 lz4hc [zstd] deflate 842
```

zstd is the active compressor, the package config agrees (`CONFIG_ZRAM_DEF_COMP_ZSTD=y`), and the device is 3924819968 bytes (≈3.9 GB) on a 3.7 GiB machine. `vm.swappiness=150`. `zswap.enabled=0` in the cmdline while zram is active.

That logical capacity is approximately full visible RAM, not the half-RAM policy described for the separate community ALARM image. It is not physical allocated memory. Confirm `mm_stat`, backing_dev, bd_stat and runtime zswap before comparing compressors at matched capacity/swappiness. Zstd CPU cost and memory saved require real browser/build memory-pressure trials; ordinary RAM-only zram has no AES cost. Do not swapoff populated zram under pressure.

## Memory configuration worth measuring

- `CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y`, `CONFIG_ARM64_4K_PAGES=y`. THP *always* is a known mixed blessing on 4GB ARM: it can amplify memory pressure and latency under fragmentation. The alternative (`madvise`) costs peak throughput on some workloads. Measure, do not assume.
- `CmaTotal: 65536 kB`, `CmaFree: 30816 kB`. The earlier hardware audit recorded nearly-full CMA usage at one instant and correctly refused to enlarge it. Unchanged here, still unproven either way.
- `CONFIG_LRU_GEN=y`, `CONFIG_LRU_GEN_ENABLED=y`. Relevant to the swappiness discussion above.

## Hardware video decode is entirely absent, and that is the media gap

```
ls /dev/video* /dev/media* → (none)
```

No usable Pi V4L2 hardware decode path has been demonstrated. `ffmpeg -hwaccels` lists compiled interfaces, not working decoders. Exact mainline Linux 7.3 contains no bcm2835-codec/bcm2835-isp/rpivid source: the earlier codec Kconfig citation was downstream Raspberry Pi source. Enabling VCHIQ alone cannot create absent codec drivers. Prefer upstream driver integration; any maintained downstream candidate needs a documented reason, coherent source/userspace/DT packages and functional playback/browser validation. Never copy foreign-ABI modules. Unicam capture is separate, requires sensor/DT/userspace qualification, and is not video decode.

## Interfaces, storage and platform limits

- **PCIe is at `Speed 5GT/s, Width x1`** (PCIe 2.0 x1), consistent with VIA's VL805 endpoint specification. Pi 5 Gen 3 tuning does not apply to this Pi 4 USB SSD path. Remove Gen 3 from the experiment queue; link speed alone does not identify the bottleneck.
- `usbfs_memory_mb=16`, `autosuspend=2` are observations, not proof of a block-I/O limit. Establish USB/UAS/bridge/error evidence before changing policy.

- Scheduler is `kyber` on the SSD and the SD card. `discard_max_bytes=0` was recorded earlier: the USB bridge does not advertise UNMAP, so `allow-discards` in the crypttab is inert. Not a bug, but do not attribute TRIM benefits here.
- `arm_boost=1` is already in the firmware config; the tuning docs are not proposing anything new there.

## What must be measured on a real 8GB board, not inferred

Everything above was measured on the 4GB model. These are the items where 8GB changes the answer and no inference is safe:

1. **zram sizing and swappiness.** The measured 4GB device has full-visible-RAM logical capacity and swappiness 150. The actual 8GB configuration is unknown; the right size and the right compressor may differ, and the 4GB result must not simply be copied.
2. **Whether translator/hugepage behaviour differs.** THP-always on 8GB has far more room to fragment before it hurts, so a 4GB result may not transfer.
3. **CMA and `gpu_mem` floors.** Same absolute reservation on double the RAM is a smaller fraction; the "do not enlarge CMA" conclusion needs re-checking rather than repeating.
4. **Build parallelism.** `pi-tuning.md` caps makepkg at two jobs on 4GB. That cap is a RAM limit, not a core limit (the board has four), so 8GB should allow more — measure actual peak RSS during a real package build before raising it.
5. **Sustained thermal behaviour at the higher clock.** A 4GB board and an 8GB board of the same revision should behave alike, but the sustained-load clock drop documented above must be re-measured rather than assumed identical.

## Suggested order for the implementer

1. Repair/version evidence and verify recovery before candidate installation; finish functional defects in their owning upstream layers.
2. Audit selected supported software XTS and bounded encrypted-file workloads, preserving encryption/security.
3. Resolve firmware clock/throttle telemetry before interpreting sustained CPU policy differences; retain schedutil absent repeatable gains.
4. Measure zram compressor/size/swappiness separately using real memory-pressure workloads and safe boot transitions.
5. Build manageable real packages, separating CPU tuning, optimization level and LTO; preserve shared aarch64 compatibility.
6. Pursue coherent upstream media support with matching userspace and functional video/browser evidence.
7. Profile storage/USB below the supported Gen 2 ceiling, without speculative link/USB settings.

## Boundaries this discovery respected

No file was modified outside this checkout. No package was installed, no service restarted, no display woken and no reboot was triggered for measurement (the one reboot in this session was the authorized kernel install). The historical pass included privileged reads and state-changing module-load attempts: `dmesg`, `/etc/crypttab`, `cryptsetup benchmark`, `/sys/kernel/debug/clk`, and `modprobe` of three crypto modules — the two that failed left nothing loaded, so the board is in the state it was found in.

Measurements quoted here are single samples on a shared desktop with the compositor running, at 45–54 °C. They are good enough to rank hypotheses and not good enough to certify a release; new comparisons must use reviewed versioned measurement semantics and matched conditions, not reuse the defective legacy probe.

## Implementation evidence update — November 8

The discovery hypotheses above are now followed by controlled implementation evidence in [the progress ledger](omarchy-pi-implementation-progress.md). Governor and software-XTS candidates showed no useful repeatable gain and were restored. [Real zstd compiler screening](../results/pi4-4gb-native/2026-11-08/zstd-source-screen/README.md) is retained with variability and size tradeoffs; it does not justify a shipping compiler default. [Current memory evidence](../results/pi4-4gb-native/2026-11-08/memory-checkpoint/README.md) shows no demonstrated global pressure. CMA occupancy is not GPU attribution, and zram payload is too small to motivate a compressor trial.

For future THP/reclaim analysis, the installed kernel is not pristine in that subsystem: saved recipe patches 8204–8207 alter allocator/reclaim hint propagation and classify opportunistic hugepage requests. The initial primary audit scoped other files; do not extend its no-overlap finding to mm/page_alloc.c. Exact excerpts and hashes are in tools/pi-experiments/low-level-source-evidence.json and [the low-level plan](omarchy-pi-low-level-next-experiments.md). Top-level THP `always`, 2 MiB `inherit`, smaller sizes `never` and defrag `madvise` were read from the live board; no policy change has occurred.

A coherent inactive VCSM/MMAL/H.264 source port has compiled and passed modpost against matching 7.3-32.1 headers, but service lifetime ownership still blocks deployment. This does not establish a usable video device, decoded frames, browser acceleration or throughput. GPU compute and browser/THP harnesses have distinct calibration/runtime gates; no capability or user-visible gain is inferred from source preparation.

## CTS and media implementation evidence correction

The Bluetooth hypothesis is now narrowed by [powered-window observations](../results/pi4-4gb-native/2026-11-08/bluetooth-cts-window/README.md) and an exact upstream AUX hardware flow-control fix missing from the recorded source. The inactive backport and DT opt-in are source-tested, not physically qualified. Driver/DT/package/recovery validation must remain coherent; no working radio is claimed.

The H.264 research series now has eleven patches, but only the first six have module-build evidence. Later production-body host tests repair specific ownership paths while a silent peer or missing RELEASED can still block teardown indefinitely. The prior OPENING requeue diagnosis was disproved by actual production queue/parser behavior. Treat this as a nondeployable source experiment, not available decode acceleration. Full-feature zstd compilation/tests continue under a reviewed temporary VM memory increase after preserved OOM and swap-layout failures; reduced compiler screening still does not justify any global shipping default.

## Measured full-package compiler follow-up

The complete, feature-equivalent O2/O3 pair has now been measured on this exact native4GB Pi4 with portable ISA and unchanged hardening. All six corpus/level units passed, totaling72 measured calls and12 excluded calibrations. Paired median decode throughput improves6.64–8.83%; compression is mixed and regresses atlevel9. The O3 library is320KiB/38.36% larger, with unchanged compressed sizes. See [complete evidence and interpretation](../results/pi4-4gb-native/2026-11-08/zstd-full-package-pair/README.md) and [independent review](omarchy-pi-zstd-matched-result-review.md). These results supersede reduced-CLI screening only for the tested full-package workloads. They do not establish stock flags, application/desktop gains, energy savings, PiOS parity or another RAM/board cohort. Candidates remain uninstalled pending application-level validation.

## H264 build acceptance and CTS boot validation boundary

The exact twelve-patch H264 series compiles all four modules with modpost/link/BTF and matching CRC, namespace, DWARF5 and vermagic checks. Headers remain unchanged; the prior eleven-patch API failure is preserved. This closes the build integration gate only. Firmware and lifecycle qualification remain unresolved and the modules remain NONDEPLOYABLE. Durable selected evidence is under results/pi4-4gb-native/2026-11-08/h264-combined-12/; see [build report](omarchy-pi-h264-combined-12-build.md). New allocation is about236.1MB plus1MiB allowance, VM2GiB unchanged, overall conservative growth remains below15GB. All build containers stopped.

The owner confirmed encrypted-console availability. Parent freshly rechecked installed CTS versions/module/UKI, firmware helper, native boot verifier and clean system health, then issued one controlled reboot. SSH disconnected as expected. Post-reboot driver/FDT/radio acceptance and rollback remain pending; no Bluetooth success is inferred. Desktop checks remain deferred under the headless instruction.
