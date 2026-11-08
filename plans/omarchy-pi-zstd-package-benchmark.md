# Parent-only matched full-package zstd benchmark

Status: measurement protocol **version 2** implemented and host logic tested; native v2 gate/calibration/measurement remain parent-only and have not run. The parent reports that the original native gate passed after correcting transfer metadata, then `nativebench1` completed six calibration trials and rejected the five-minute projection before **any measured blocks**. This is a rejected attempt, not a performance result. Raw native evidence remains on the Pi for the parent to retrieve.

Ownership is only this plan and `tools/pi-experiments/zstd-package-benchmark.py` (including embedded focused tests), plus a new ignored preservation directory under `build/`. This implementation session used tiny host Python checks only: no Pi access, SSH, Docker/VM, builds, package execution, benchmarks, staging, commits, messages or delegation. The user resumed after clearing 20 GB and set a **15 GB hard storage ceiling**; the parent reserves **512 MB total artifacts**, not additional build storage. Storage coordination, the physical Pi and the active CTS build lane remain parent-owned. This change creates less than 2 MB of local preservation/test artifacts and changes no CTS files.

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

Transfer the new runner and the **entire** bundle directory with the parent's existing authenticated SSH transport, preserving symlinks and modes (for example an archive or rsync with `-a`). Keep stock/O2/O3 directories separate. Retain transfer command, output and both recorded hashes. Use the successful Python-tar transfer approach or equivalent metadata-clean transport: the first macOS tar transfer added AppleDouble files and was correctly rejected by exact bundle inventory. Do not weaken the inventory check or reuse that rejected bundle. On the target, compare `sha256sum` for the runner and manifest against the controller's independently retained values before executing. Do not execute the package-build orchestrator or copy a builder loader to the Pi. Do not use sudo for this runner.

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

## Protocol v1 history and rejected native attempt

The original protocol timed stock/O2/O3 on both corpora at levels1/3/9 in all six three-variant permutations: **108 measured trials**, plus six fresh level9 calibration trials (all three variants on both corpora). Each variant occupied each position twice and each pair had 3:3 relative order. Projection was maximum calibration lifecycle cost × 108 × 1.15 against the remaining 300-second budget. This protocol remains historical, not the current execution plan.

The parent reports: initial macOS-tar transfer failed inventory due to AppleDouble extras; a second Python-tar transfer passed the complete native gate, including all formats, wrappers, legacy, dictionary and cross-decode. Attempt identity **`nativebench1`** then ran all six v1 calibration trials and rejected with `calibration rejects five-minute budget; retain, redesign explicitly` before any measured blocks. No throughput conclusion follows. Native absolute output paths, result hashes and raw logs must be supplied/retrieved by the parent; this sub-agent has not accessed them. Preserve that rejected attempt independently of v2. Its calibrations must never be selected or relabeled as measured observations.

## Bounded benchmark: measurement protocol version 2

After a complete gate, the parent may execute:

```bash
python3 /absolute/zstd-package-benchmark.py bench \
  --bundle /absolute/zstd-package-bundle --out /absolute/new/zstd-package-benchmark \
  --gate /absolute/zstd-package-gate/results.json --cpu 2 --exclusive-pi \
  --conditions 'same native 4GB Pi conditions as the gate; no competing load'
```

The gate's runner/manifest hashes, dependency-provider fingerprints, loader and policy/session/package context must match this invocation. Reboot changes are rejected. There is no privileged collector or automatic session setup. Results remain in the chosen output path even when rejected.

The five-minute (300-second) monotonic deadline still covers preflight, calibration, cooling and all trials in each invocation. **A new runner hash and fresh complete native gate are mandatory before v2 measurement**: the benchmark compares the gate's runner hash to its own, so the old successful gate cannot authorize this changed runner. Keep provenance and native correctness on all three variants unchanged. Stock remains context-only provenance/native correctness; no stock timing is collected in v2.

Four fresh short calibration trials run first: O2 and O3 on each of the two corpora at level9, `--single-thread -b9 -i1`, CPU2 affinity. Calibration warms the actual corpus/load path and is retained with phase `calibration`, excluded from measured blocks. Projection is **maximum of these four observed lifecycle costs × 72 actual new measured invocations × 1.15**. Costs include guards/cooling; calibration elapsed time has already consumed the deadline and is not counted as measurement. If projection exceeds remaining budget, stop before measured blocks and preserve the rejected attempt. No deadline extension, selective calibration reuse, native-check removal or silent repetition reduction is allowed. V2 may still reject on this board; host tests establish no native timing feasibility.

The measured matrix is **2 variants × 2 public corpora × 3 levels × 6 paired blocks = 72 new invocations**. Every invocation uses `--single-thread -bLEVEL -i1` and reports both compression and decode internal operation throughput. With A=O2 and B=O3, block order is **AB, BA, AB, BA, AB, BA**: three AB and three BA blocks, each variant occupying each position three times for every corpus/level. Jobs are corpus-name sorted with levels1/3/9, reversed on alternate blocks; the pair stays adjacent within each job. All timed variants share affinity, loader, corpus, command shape, environment and cache approach. Page cache is warm by use; no cache flush or cold-storage claim is made. Never pool corpora or levels or mix calibration into measured distributions. Report all six block values with medians/ranges and paired O2/O3 differences. No stock speed comparison is provided by v2.

## Stops, telemetry and interpretation

Before trials and after completion the runner rejects session/output, governor/min/max/driver, CPU-online, boot/kernel or package-version drift and rechecks provider/loader hashes. The observed changed context is retained on drift. Every trial starts at at most 52°C. Cooling consumes the same deadline. During a child, sampled native temperatures at **70°C or greater** or any native `in0_lcrit_alarm` other than exactly `0` stops the process group; missing sensors also stop. Requested cpufreq is only a policy snapshot. Firmware actual clocks, throttle history and energy are explicit null/unknown; native voltage alarms do not establish historical firmware throttle state. No CPU/GPU clock-time inference or energy-efficiency claim is valid.

Each child has a 25-second wall deadline, 20/21-second soft/hard CPU limit, 512 MiB virtual-address limit, 64 MiB per-file limit, sanitized environment, and one-CPU affinity. These bounds may expose a legitimate target/runtime requirement; such a failure is a rejected attempt, not a speed result. The small T2 correctness smoke can create two workers pinned to the same core; all performance trials remain single-thread. Stop paths kill the child process group and reap it. Ctrl-C, mismatches, deadlines and health stops preserve status and evidence. No cleanup discards temporary files or raw output; parent removes the private result tree only after evidence transfer/review. Sampling is finite and only active during this experiment, not an idle daemon.

Results format:

- `manifest.json` in the bundle records all input hashes, sizes, regular-file modes, symlink targets, public corpus origins and comparison labels.
- `results.json` records status/reason, runner/manifest/gate hashes, board/context, provider/loader fingerprints, explicit unknowns, calibration projection, every command and trial linkage. `measurement_protocol_version` explicitly identifies v2; benchmark `measurement_protocol` records variants, corpora, levels, six balanced orders, counts, CLI, deadline, headroom and the complete planned schedule. `calibration.records` links each corpus/variant/level9 lifecycle cost to its trial index and raw command; projection records 72 new trials and 15% headroom. `trials` records actual phase/block/order through its ordered entries, including partial/rejected attempts. Trial `compression_MB_s` and `decode_MB_s` are actual CLI **internal algorithm** rates, decimal MB/s, parsed only from a complete matched-input rate pair. Compressed bytes are retained.
- `NNNN.stdout`, `NNNN.stderr` and optional `NNNN.stdin` preserve each raw command stream separately, including binary smoke inputs/outputs and rejected commands. Command records contain exact argv/environment, UTC start, exit/stop reason, lifecycle wall seconds, individual child user/system CPU seconds, maximum RSS in Linux KiB and context switches where completed. Wall includes loader/startup, corpus reads, I/O and bounded sampling wait; CPU includes the complete child process, not a pure algorithm counter. Do not divide corpus bytes by this wrapper wall and call it zstd's internal throughput. It is not a package-manager or disk benchmark.
- `health.jsonl` retains temperatures, native voltage alarms, requested frequencies, PSI, load and memory state including the sample triggering a safety stop. `tmp/` retains dictionaries and sample files. Review private paths/session metadata before publishing; no credentials are collected.

No statistical claim should survive a rejected/partial matrix. Preserve all calibration, failures and stops beside the successful run; never select only the fastest observations. Even a complete matrix establishes only this public corpus/levels/native 4GB Pi cohort and cannot justify a global O3 change, application latency claim, Raspberry Pi OS parity, or extrapolation to Pi 5/8GB boards.

## Local verification

Embedded host-only tests exercise real rate parsing (including wrong-size/zero/incomplete rejection), actual paired scheduling for every corpus/level, positional/pair order balance, reversed workload order, four calibration jobs and conservative 72-trial projection, hash mismatch rejection, foreign/missing loader-provider rejection using temporary files, and UTF-8 legacy text versus binary escaped fixture parsing. A focused test drives `Runner.bench` itself with native execution/health substituted to verify four calibration then 72 measured calls, original CLI shape and explicit v2 result metadata. Synthetic parsed rates in that orchestration test validate no performance behavior and execute no package code.

```bash
python3 tools/pi-experiments/zstd-package-benchmark.py self-test >build/local-zstd-protocol-v2-preserved/v2-self-test.log 2>&1
cat build/local-zstd-protocol-v2-preserved/v2-self-test.log
```

Six tests passed. Seven in-memory wrong-protocol mutations each failed the relevant tests: unbalanced 4AB/2BA blocks, restoring 108 stock-inclusive measured calls, projecting 108 instead of 72, subtracting calibration from fresh measured count, dropping 15% headroom, omitting O3 calibration, and substituting stock in actual measured dispatch. Full run output is retained in `build/local-zstd-protocol-v2-preserved/v2-self-test.log` and `v2-mutations.log`. Native ABI/loading, telemetry, full-feature correctness, calibration and performance still require the parent's fresh execution gates.

The ignored local preservation directory `build/local-zstd-protocol-v2-preserved/` retains the complete original runner (including all original embedded tests), original plan, all five available original `/tmp/zstd-package-benchmark*.log` files unchanged, and `preserved.json` with their hashes. The original runner SHA-256 is `d35d0f249c0017ca3792c961c10224e297ab77d8fd6f6dcd848b880c78d0bb1a`. The old four-test pass and original four red-mutation evidence remain intact; the order test is explicitly adapted for v2 rather than silently treating the old permutation protocol as current. Native raw run logs remain on the Pi and are not represented as locally archived. Parent retrieval must preserve them in full within the total artifact allowance.
