# Bounded system bsdtar / full libzstd package-listing follow-up

Prepared 2026-11-08; implementation and host logic checks only. No application execution or native result exists for this follow-up. The parent exclusively owns the Pi, CTS install/recovery work, physical changes, evidence transfer and measurement scheduling. Run nothing here until that work is qualified and the parent has a quiet exclusive Pi window. No package install, source fetch, build, cache flush, CPU policy change, LD_PRELOAD or system-library replacement is involved.

## Question and fixed input

Does substituting the existing authenticated full O3 libzstd for the matched full O2 library improve elapsed time for the unchanged system `/usr/bin/bsdtar -tf ARCHIVE` through its unchanged system libarchive? This is application listing, including archive reads/decode, tar metadata traversal and writing the listing to a retained stdout file. It is neither extraction nor a package-manager transaction. The actual loader receives `--library-path` containing exactly one `libzstd.so.1` symlink into that variant's existing full-library bundle. All other dependency providers must equal the default system-loader trace. No benefit is assumed if storage, metadata traversal or stdout dominates.

The source is the existing real `linux-omarchy-7.3-32.1-aarch64.pkg.tar.zst`, exactly **181666855 bytes**, SHA-256 `2164fb79c02442b9047166b07f1667558f1674c2ccf345d38b9f7e10e97ef8d8`. The parent chooses its existing candidate-cache location. The runner only reads this file and records path/device/inode/mtime/size/hash; every stable check rehashes it and rejects identity drift. Hashing and prior listings make reads explicitly warm; this is no cold-cache/storage-isolation experiment. The fixed source package does not require the running kernel to be 32.1, but a changed kernel/boot requires fresh qualification and a separate cohort.

## Preconditions and evidence gates

Read `plans/omarchy-pi-zstd-package-benchmark.md`, `plans/omarchy-pi-zstd-matched-result-review.md`, the real runner, and `results/pi4-4gb-native/2026-11-08/zstd-full-package-pair/summary.json`. The earlier six units establish descriptive internal algorithm decode improvements, mixed compression and a 320 KiB larger O3 library; they establish no application latency improvement. The review's missing raw-gate availability objection was addressed by subsequent parent retrieval, without an independent recheck implied. Preserve those historical observations separately.

`tools/pi-experiments/zstd-package-listing.py` imports the adjacent unchanged `zstd-package-benchmark.py`, pinned to SHA-256 `bf40ba15e4eb370c35f8fc2a525dd87033748a0d4df27d457f72fbad6e365bf0`. It reuses actual `Runner.verify`, health, context, stable checks, sanitized environment, resource limits, process-group termination, evidence persistence and rejection boundary. It changes neither the old runner nor its protocols/trust gates. A future base-runner change deliberately rejects this script until explicitly reviewed and repinned.

First obtain a fresh complete full native v3 gate using the existing authenticated bundle after all CTS/physical changes. Both new modes require that gate and compare its runner, manifest, boot/kernel/policy/session/package context, provider fingerprints and actual loader with fresh verification. The old all-format, legacy, dictionary, wrappers and cross-decode correctness checks remain mandatory; application checks supplement them. A successful gate from before a reboot, dependency change or session/output/policy change cannot qualify the follow-up. Keep the raw native gate and its hash, not just its success summary.

The separate application `gate` additionally records system bsdtar's hash, ELF header/program interpreter, dynamic libarchive dependency and symbol versions, libarchive's dynamic libzstd dependency and versions, libarchive package version, actual system-loader `--verify` and default `--list`, and all stock/O2/O3 application loader traces. It hashes every parsed provider and actual loader; requires all non-zstd providers to remain identical; checks each selected full-library hash against the existing pinned bundle; and executes `--version` under each provider to resolve normal ABI/version requirements on target. The three isolated directories contain only their own libzstd symlink; no alternate dependency bundle or preload is exposed. This is an application ABI smoke, not exhaustive dependency ecosystem qualification.

The application gate lists the fixed archive under stock, O2 and O3. Its successful stock stdout supplies the expected exact SHA-256, byte count and positive nonempty newline-delimited path count; both candidates must match it. This derives the archive-specific count from the actual authenticated input and stock implementation rather than baking a count into a source-change test. Blank paths, NULs, unterminated output, stderr warnings and output larger than 2 MiB reject. The kernel package's member names are assumed newline-free. Every later calibration/measured listing must match all three expected fields. Raw stdout is retained for independent byte-for-byte comparison. The benchmark links the complete application gate and compares all relevant context, identities and fingerprints before proceeding.

## Measurement protocol

Each new gate or benchmark invocation has its own original **300-second monotonic deadline**, covering preflight, guards, hashing, cooling and all child work. Benchmark performs exactly two fresh same-workload calibrations, **O3 then O2**, followed by six paired blocks **BA, AB, BA, AB, BA, AB**, A=O2 and B=O3. There are twelve measured calls, six per variant, with three starts each, reversing the earlier AB-first experiment. Stock is correctness context only. No calibration observation enters the measured summary. Projection is max(two full fresh calibration lifecycle costs) × 12 × 1.15 against the remaining original budget. Rejection preserves the attempt; do not extend time, omit blocks or reuse calibration to rescue it.

The inherited guards require the native normal-user c03115 Pi 4 4GB cohort, CPU2 affinity, parent's explicit exclusive-Pi assertion, fixed existing policies and session/output state, cool admission at ≤52°C, stop at sampled ≥70°C, and native voltage alarms exactly zero. Lock expectation defaults to `true`; explicit `false` supports the parent's unlocked cohort without changing it. Context/provider/archive drift rejects the entire attempt. Cooling and the post-cool stable check precede launch; the threshold is sampled admission, not continuous exact-launch temperature proof. Child limits remain 25 seconds wall, 20/21 seconds CPU, 512 MiB virtual address space and 64 MiB per output file; all raw streams and health samples survive rejection. Admission requires 640 MiB free space (512 MiB reserve plus 128 MiB evidence headroom). New checks retain at least 512 MiB filesystem free space and reject evidence trees reaching 128 MiB. With ≤2 MiB valid listings, fourteen timed streams plus the three separate gate listings remain modest (expected roughly 15–20 MB for this archive); preserve all, never truncate to meet reserve. A runaway child's final stream may exceed the aggregate check before rejection, bounded by inherited file limits. Parent must account for both result trees plus native-gate evidence within its remaining artifact allowance before starting.

Child wall seconds cover loader/startup, archive read/decode, metadata and stdout filesystem writes plus sampled waiting overhead. User/system CPU and Linux wait4 max RSS describe the complete child lifecycle. RSS may include the fork/preexec parent's high-water footprint; it is not library-only memory. Guard/hash/cooling costs are outside reported child wall but included in calibration lifecycle projection and the five-minute bound. Results retain individual command metrics and summarize all six observations per variant with medians/ranges and per-block signed O3−O2 differences for wall, user CPU, system CPU and RSS. Lower elapsed time is better; report every pair and regressions. There are no internal zstd MB/s rates, byte/wall-derived algorithm claims, firmware actual clock/throttle measurements or energy estimates.

## Parent-only commands after CTS and recovery qualification

Use authenticated transfer/hash verification for both adjacent scripts. Set the absolute paths below to the parent's chosen existing paths. Create only the new result root; each leaf must be absent. Keep the normal graphical session environment. Execute serially, with no CTS workload, other benchmark, install or competing application work. These are prepared commands, not commands executed by this implementation session.

```bash
runner=/absolute/tools/pi-experiments/zstd-package-benchmark.py
listing=/absolute/tools/pi-experiments/zstd-package-listing.py
bundle=/absolute/existing/zstd-package-bundle
archive=/absolute/existing/candidate-cache/linux-omarchy-7.3-32.1-aarch64.pkg.tar.zst
results=/absolute/new/zstd-package-listing-cohort
conditions='native 4GB Pi; post-CTS physically qualified; exclusive quiet window; fixed supply/cooling/display; explicit unlocked session; existing CPU policy; warm reads; encrypted USB SSD'
mkdir -m 700 "$results"
python3 "$runner" gate --bundle "$bundle" --out "$results/native-gate" --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions" >"$results/native-gate.log" 2>&1
```

Inspect and preserve the complete native gate; proceed only when its `results.json` is complete and no guard failed. Run application correctness next:

```bash
python3 "$listing" gate --bundle "$bundle" --archive "$archive" --native-gate "$results/native-gate/results.json" --out "$results/application-gate" --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions" >"$results/application-gate.log" 2>&1
```

Inspect the three raw listings, their exact hash/bytes/positive count agreement, application traces/provider hashes and complete status. Only then measure:

```bash
python3 "$listing" bench --bundle "$bundle" --archive "$archive" --native-gate "$results/native-gate/results.json" --gate "$results/application-gate/results.json" --out "$results/listing-unit" --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions" >"$results/listing-unit.log" 2>&1
```

Preserve rejected attempts without relabeling them. Retrieve every raw stdout/stderr, results.json, health.jsonl and top-level log from all three stages. Independently recompute listing equality and six paired metrics from command records; do not substitute the summary for raw evidence. No successful partial run establishes a completed unit. A complete unit supports only warm listing of this fixed package in this exact cohort. It does not qualify extraction, install/rollback, global O3, performance versus stock, Raspberry Pi OS parity, energy efficiency, Pi 5 or an 8GB board.

## Host verification

Three embedded host-only tests exercise exact listing parsing/hash/count rejection, reversed balanced scheduling and conservative projection, and real temporary-file hash/provider mismatch guards. They execute no package/application code or fake performance benchmark. The test fixture has two arbitrary paths, not this archive's expected count. In-memory mutants for incorrect count, constant hash, AB-first ordering and omitted projection headroom failed their focused tests as required; complete output is retained in `/tmp/zstd-package-listing-mutations.log`.

```bash
python3 tools/pi-experiments/zstd-package-listing.py self-test >/tmp/zstd-package-listing-self-test.log 2>&1
cat /tmp/zstd-package-listing-self-test.log
```

Host result: three tests pass and all four focused mutants fail as required. Syntax parsing and whitespace checks also pass; the imported base runner still matches its pinned hash. Implementation artifacts consist only of this plan, the new script and tiny host logs under `/tmp`, below 2 MiB. No Pi/SSH/Docker/build/install/source fetch, benchmark/application execution, staging, commits, external messages or subagents were used. Native correctness, ABI loading, health, calibration feasibility and measured effects remain pending the parent's window.
