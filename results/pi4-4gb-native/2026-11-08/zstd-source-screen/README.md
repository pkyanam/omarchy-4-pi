# Zstd compiler screening on the physical 4GB Pi

Status: complete bounded screening; no system binary, library, compiler defaults, governor or memory policy changed. Three isolated v1.5.7 candidates had passed 520 local correctness checks before transfer. Parent verified bundle/binary/corpus hashes and libc compatibility, then executed them on the Pi. Source/build provenance is in plans/omarchy-pi-zstd-compiler-experiment.md and its retained ignored build directory. The tracked reproducer is tools/pi-experiments/zstd-pi-screen.py; the build/correctness recipe is build-zstd-candidates.sh.

Five alternating forward/reverse measured blocks followed one warmup block. Each variant used CPU2, --single-thread -b3 -i1 and the exact official-source corpus (8919040 bytes, SHA-256 f1cb05ca79a264c240772c789429fc6ecd0d9e5fcd8be5fdeb98338841d65d2c). This bounded subset is not the handoff's full eight-block/corpus/level matrix. Every raw CLI log and all telemetry are retained here, including warmups. Zstd benchzstd.h defines MB_UNIT=1000000, so rates below are decimal MB/s, not MiB/s. CLI internal operation rates are used; controller wall time has 0.2-second sampling quantization and must not be treated as exact utilization.

| Variant | Compression median / range MB/s | Decompression median / range MB/s |
| --- | --- | --- |
| Experimental generic O2 |48.4 /46.9–49.0|392.4 /386.4–392.9|
| A72 scheduling, O2 |48.4 /47.8–49.0|386.8 /382.1–397.8|
| Generic O3 |49.0 /48.8–49.5|413.4 /404.3–417.0|
| Installed stock context |48.5 /48.0–48.9|392.5 /374.0–393.8|

Tuning produced no compression gain. O3 compression's approximately 1.2% median increase over experimental O2 is inside that baseline's variation. O3 decompression's approximately 5.35% higher median is consistent across this screen and merits longer/reversed confirmation, not a shipping decision. Its unstripped test executable is 42.16% larger. Upstream defaults to O3; experimental O2 does not reconstruct the installed package's compiler flags. Stock packaging/features/toolchain can differ, so stock is contextual rather than a compiler-variable control. All candidates retain the portable armv8-a ISA; no -mcpu/native crypto/LSE or global O3 was applied.

Starting temperatures were 50.634–52°C (the controller enforced at most 52°C before every trial); sampled peak 54.530°C, native voltage alarms stayed 0, and the same locked desktop/output state was enforced before every trial and at completion. Governor remained schedutil. Raw requested-frequency and PSI observations are in results.json. Firmware actual clocks/throttle history and energy remain unknown. This is in-memory real zstd algorithm work, not disk, kernel zram, package-manager latency, browser/desktop performance or Raspberry Pi OS parity. No 8GB/Pi 5 sample was used.

Next gate: repeat longer balanced O2/O3 trials and broader corpus/levels, then evaluate a complete normally packaged candidate with optional-format/features preserved and actual package/application workload time. Retain failures and size tradeoffs. Do not promote on this screen alone.

Plot: trials.svg; inline chart source: trials.html; parsed medians/ranges: summary.json. No raw sample was dropped to improve the comparison.
