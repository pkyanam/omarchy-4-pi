# Parent-only matched full-package zstd benchmark

Status: prepared and host logic tested; **no Pi execution, calibration, benchmark, installation or performance result**. Ownership is only this plan and `tools/pi-experiments/zstd-package-benchmark.py` (including its embedded focused tests). Existing package evidence, metrics tools and source-screen results are read-only. No SSH, Docker/VM, compilers, dependency installation, staging, commits, external status/messages or delegation were used. The parent's restored OrbStack limit (2048 MiB configured, 2074386432 bytes observed, one CPU) is unrelated to this runner; storage work and full CTS builds remain parent-owned.

## Evidence boundary

Both complete packages passed unchanged upstream tests and pair audits in `build/upstream-pi/stable-4.5/zstd-package-candidates/attempt-3072m-swap0/`; use that attempt only. `transfer-manifest.json` pins archive, CLI and library hashes. Both candidates use the same toolchain, source, portable armv8-a ISA, hardening, dependencies, features and normalized compiler/link/cache inputs, varying O2/O3. Installed stock CLI and library correspond to the authenticated archive, but stock's original ARM recipe and optimization flags remain unknown. Stock is a contextual comparison with differing unknown build history, never the optimization-variable control. No O0 comparison, GPU timing comparison, global tuning promotion or win claim follows.

The earlier source screen used reduced experimental CLIs and level3 only. Its approximately 5.35% O3 decode observation is a follow-up hypothesis, not qualification of these packages. The new runner executes full extracted package CLIs and libraries, with explicit system-loader invocations and each variant's own library directory. It never installs a package, replaces `/usr/bin/zstd` or `/usr/lib/libzstd*`, changes governors, drops caches, or writes sysfs. Normal Linux user, Python 3.12+, existing readelf, pacman, Hyprland and omarchy-shell are required; do not install dependencies automatically.

## Fixed public corpus and isolation

`prepare` only copies/extracts existing pinned archives; it does not execute them. It creates an exclusive new directory, uses Python's tar data filter, verifies archive/CLI/library hashes, and inventories all retained regular files, modes and internal symlinks. Keep its printed manifest SHA-256 through authenticated transfer: the native runner checks the inventory, but an editable manifest is not a signature. The known archive/CLI/library/corpus hashes are also compiled into the runner. Full packages, including wrappers, pzstd and metadata, remain in isolated `stock/`, `O2/` and `O3/` trees. O2/O3 archive basenames coincide: never flatten those directories.

The two immutable inputs total less than 10 MiB, well below the 32 MiB aggregate cap:

| Corpus | Provenance | SHA-256 |
| --- | --- | --- |
| `corpus/source.tar` (8919040 bytes) | Exact official zstd v1.5.7 source tar from the prior source screen | `f1cb05ca79a264c240772c789429fc6ecd0d9e5fcd8be5fdeb98338841d65d2c` |
| `corpus/stock-libzstd.elf` | Real public binary: library from the authenticated stock archive, copied unchanged | `14d907be630eb1670d14fc104a0982cca01feac5bc75f1846e54f6278c5ee2e2` |

These represent source/package-content and ELF workloads, not all application data. No private files, synthetic zero/counter payloads, runtime downloads or private filesystem traversal enter the corpus. The gate uses public source test files and fixtures from this same pinned tar.

## Concrete parent preparation and transfer

On the controller, from the repository root, choose a new output path. These commands are instructions for the parent; this implementation session did not run prepare or any target command.

```bash
python3 tools/pi-experiments/zstd-package-benchmark.py prepare \
  --attempt build/upstream-pi/stable-4.5/zstd-package-candidates/attempt-3072m-swap0 \
  --stock build/upstream-pi/stable-4.5/zstd-package-candidates/zstd-1.5.7-3-aarch64.pkg.tar.xz \
  --source build/upstream-pi/stable-4.5/zstd-compiler-candidates/corpus/source.tar \
  --out /absolute/new/private/zstd-package-bundle
shasum -a 256 tools/pi-experiments/zstd-package-benchmark.py /absolute/new/private/zstd-package-bundle/manifest.json
```

Transfer the runner and the **entire** bundle directory with the parent's existing authenticated SSH transport, preserving symlinks and modes (for example an archive or rsync with `-a`). Keep stock/O2/O3 directories separate. Retain transfer command, output and both recorded hashes. On the target, compare `sha256sum` for the runner and manifest against the controller's independently retained values before executing. Do not execute the package-build orchestrator or copy a builder loader to the Pi. Do not use sudo for this runner.

The parent must own an exclusive physical-Pi window: no concurrent storage tests, CTS load, tuning, package transactions or other measurements. Establish the existing locked graphical session and unchanged output geometry/scale/DPMS, cooling, supply and background workload; supply concise non-sensitive conditions. The flag is an explicit ownership assertion, not a machine-wide lock or an idle detector. The runner cannot exclude an unrelated user's workload automatically. Normal-user session queries need the existing XDG_RUNTIME_DIR, HYPRLAND_INSTANCE_SIGNATURE, WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS and OMARCHY_PATH where present; it inherits only those session variables into an otherwise sanitized child environment. No LD_PRELOAD/LD_LIBRARY_PATH inheritance occurs.

## Separate initial native gate

Parent only, on the Pi in the existing user's graphical session, substituting actual absolute paths:

```bash
python3 /absolute/zstd-package-benchmark.py gate \
  --bundle /absolute/zstd-package-bundle --out /absolute/new/zstd-package-gate \
  --cpu 2 --exclusive-pi \
  --conditions 'native 4GB Pi; locked desktop; fixed display/cooling/supply; no competing load; existing schedutil; warm page cache; encrypted USB SSD'
```

The gate requires Pi 4 model and exact revision c03115, normal uid, available CPU2, locked desktop and observed policies. It verifies the bundle, exact installed stock CLI/library, pinned archives, candidate CLI/library hashes, AArch64 PIE headers, version requirements and system-loader `--verify`/`--list` traces for zstd and pzstd. Every trace must resolve libzstd to that package's own extracted directory. All parsed dependency providers and the actual system-loader file are hashed. Versioned symbol requirements (including candidate GLIBC_ABI_DT_RELR) are retained through readelf output; actual target loading/version execution must succeed. This complements prior static ABI/export audits and does not prove every possible application ABI interaction.

Only after provenance succeeds does the native correctness phase run all-format zstd/gzip/xz/lzma/lz4 round trips and all-direction stock/O2/O3 cross-decode; zstd level1/3/9 cross-decode; T2, unzstd/zstdcat/zstdmt and pzstd smokes; trained dictionary round trip; malformed/truncated/golden-error rejection; supported v0.5/v0.6/v0.7/current legacy decoding and concatenation, with excluded v0.4 rejection. Each CLI invocation uses the system loader and its own library. A mismatch rejects the gate. Preserve a failed attempt and diagnose it; do not reduce features to pass. This small native smoke suite is separate from, and does not replace, the full unchanged upstream build checks.

## Bounded benchmark and calibration gap

After a complete gate, the parent may execute:

```bash
python3 /absolute/zstd-package-benchmark.py bench \
  --bundle /absolute/zstd-package-bundle --out /absolute/new/zstd-package-benchmark \
  --gate /absolute/zstd-package-gate/results.json --cpu 2 --exclusive-pi \
  --conditions 'same native 4GB Pi conditions as the gate; no competing load'
```

The gate's runner/manifest hashes, dependency-provider fingerprints, loader and policy/session/package context must match this invocation. Reboot changes are rejected. There is no privileged collector or automatic session setup. Results remain in the chosen output path even when rejected.

The five-minute monotonic deadline covers preflight, calibration, cooling and all trials in each invocation. Six short calibration trials run first: every variant on each corpus at level9, `--single-thread -b9 -i1`, with CPU2 affinity. They warm the actual corpus/load path and are retained with phase `calibration`, excluded from measured blocks. Projection uses the maximum observed trial lifecycle cost, including guards/cooling, times 108 measured invocations with 15% headroom. If that projection exceeds the remaining budget, the runner stops before measured blocks. This is deliberately conservative, not target calibration evidence. **The full matrix may not fit five minutes on this board.** The parent must review the saved projection; any smaller explicitly redesigned protocol needs a new runner/plan/gate and fresh results, not silently fewer repetitions or a longer deadline. No Pi trial has validated timing, cooling feasibility, sensor access, target session commands, safe-loader wrapper behavior or the full matrix yet.

If calibration admits the matrix, each of six measured blocks covers both corpora and levels1/3/9. Every invocation uses `--single-thread -bLEVEL -i1`, which reports compression and decode internal operation throughput. The six variant permutations give each variant each position twice and each pair both orders three times; workload order reverses on alternate blocks. All variants share affinity, loader, corpus, command shape, environment and cache approach. Page cache is warm by use; no cache flush or cold-storage claim is made. Never pool corpora or levels or mix calibration into measured distributions. Report all six block values with medians/ranges and paired O2/O3 differences; keep stock separate as context.

## Stops, telemetry and interpretation

Before trials and after completion the runner rejects session/output, governor/min/max/driver, CPU-online, boot/kernel or package-version drift and rechecks provider/loader hashes. The observed changed context is retained on drift. Every trial starts at at most 52°C. Cooling consumes the same deadline. During a child, sampled native temperatures at **70°C or greater** or any native `in0_lcrit_alarm` other than exactly `0` stops the process group; missing sensors also stop. Requested cpufreq is only a policy snapshot. Firmware actual clocks, throttle history and energy are explicit null/unknown; native voltage alarms do not establish historical firmware throttle state. No CPU/GPU clock-time inference or energy-efficiency claim is valid.

Each child has a 25-second wall deadline, 20/21-second soft/hard CPU limit, 512 MiB virtual-address limit, 64 MiB per-file limit, sanitized environment, and one-CPU affinity. These bounds may expose a legitimate target/runtime requirement; such a failure is a rejected attempt, not a speed result. The small T2 correctness smoke can create two workers pinned to the same core; all performance trials remain single-thread. Stop paths kill the child process group and reap it. Ctrl-C, mismatches, deadlines and health stops preserve status and evidence. No cleanup discards temporary files or raw output; parent removes the private result tree only after evidence transfer/review. Sampling is finite and only active during this experiment, not an idle daemon.

Results format:

- `manifest.json` in the bundle records all input hashes, sizes, regular-file modes, symlink targets, public corpus origins and comparison labels.
- `results.json` records status/reason, runner/manifest/gate hashes, board/context, provider/loader fingerprints, explicit unknowns, calibration projection, every command and trial linkage. Trial `compression_MB_s` and `decode_MB_s` are actual CLI **internal algorithm** rates, decimal MB/s, parsed only from a complete matched-input rate pair. Compressed bytes are retained.
- `NNNN.stdout`, `NNNN.stderr` and optional `NNNN.stdin` preserve each raw command stream separately, including binary smoke inputs/outputs and rejected commands. Command records contain exact argv/environment, UTC start, exit/stop reason, lifecycle wall seconds, individual child user/system CPU seconds, maximum RSS in Linux KiB and context switches where completed. Wall includes loader/startup, corpus reads, I/O and bounded sampling wait; CPU includes the complete child process, not a pure algorithm counter. Do not divide corpus bytes by this wrapper wall and call it zstd's internal throughput. It is not a package-manager or disk benchmark.
- `health.jsonl` retains temperatures, native voltage alarms, requested frequencies, PSI, load and memory state including the sample triggering a safety stop. `tmp/` retains dictionaries and sample files. Review private paths/session metadata before publishing; no credentials are collected.

No statistical claim should survive a rejected/partial matrix. Preserve all calibration, failures and stops beside the successful run; never select only the fastest observations. Even a complete matrix establishes only this public corpus/levels/native 4GB Pi cohort and cannot justify a global O3 change, application latency claim, Raspberry Pi OS parity, or extrapolation to Pi 5/8GB boards.

## Local verification

Embedded host-only tests exercise real rate parsing (including wrong-size/zero/incomplete rejection), positional/pair order balance, hash mismatch rejection, foreign/missing loader-provider rejection using temporary files, and UTF-8 legacy text versus binary escaped fixture parsing. They invoke no compiler or package code:

```bash
python3 tools/pi-experiments/zstd-package-benchmark.py self-test >/tmp/zstd-package-benchmark-tests.log 2>&1
cat /tmp/zstd-package-benchmark-tests.log
```

Four tests passed. Four in-memory red mutations (accept wrong input size, unbalanced repeated order, bypass hash mismatch, accept foreign loader directory) each made the relevant test fail; full mutation evidence is `/tmp/zstd-package-benchmark-mutations.log`. These checks establish host logic only. Native ABI/loading, telemetry, full-feature correctness, calibration and performance all remain parent execution gates.
