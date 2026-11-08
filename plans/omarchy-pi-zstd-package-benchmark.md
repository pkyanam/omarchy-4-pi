# Parent-only matched full-package zstd benchmark

Status: measurement protocol **version 3** implements explicit per-workload units and passes host-only tests. Native v3 gate/calibration/measurement remain parent-only and have not run. Parent reports `gate-v2-2` passed with runner `29e7e6a842a5be49c0b4d612c583176202a09c592b0328cc7a2a9e1ee0cc20ae`; `benchmark-v2-1` then ran four calibrations and rejected before **any measured blocks**. This is a rejected attempt with no performance or benefit claim. Parent is retrieving native evidence; this session has not accessed the Pi.

Ownership is only this plan and `tools/pi-experiments/zstd-package-benchmark.py` (including embedded focused tests), plus a new ignored preservation directory under `build/`. This implementation session used tiny host Python checks only: no Pi access, SSH, Docker/VM, builds, package execution, benchmarks, staging, commits, messages or delegation. The user resumed after clearing 20 GB and set a **15 GB hard storage ceiling**; the parent reserves **512 MB total artifacts**, not additional build storage. The concurrent CTS lane owns 1 CPU and 1536 MiB heavy-work budget; the aggregate new-growth ceiling remains 15 GB. Storage coordination, the physical Pi and the active CTS build lane remain parent-owned. This change creates less than 2 MB of local preservation/test artifacts and changes no CTS files.

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

The gate requires Pi 4 model and exact revision c03115, normal uid, available CPU2, the explicit expected lock state (default `true`) and observed policies. Use the v3 commands below for the parent's current explicit unlocked cohort. It verifies the bundle, exact installed stock CLI/library, pinned archives, candidate CLI/library hashes, AArch64 PIE headers, version requirements and system-loader `--verify`/`--list` traces for zstd and pzstd. Every trace must resolve libzstd to that package's own extracted directory. All parsed dependency providers and the actual system-loader file are hashed. Versioned symbol requirements (including candidate GLIBC_ABI_DT_RELR) are retained through readelf output; actual target loading/version execution must succeed. This complements prior static ABI/export audits and does not prove every possible application ABI interaction.

Only after provenance succeeds does the native correctness phase run all-format zstd/gzip/xz/lzma/lz4 round trips and all-direction stock/O2/O3 cross-decode; zstd level1/3/9 cross-decode; T2, unzstd/zstdcat/zstdmt and pzstd smokes; trained dictionary round trip; malformed/truncated/golden-error rejection; supported v0.5/v0.6/v0.7/current legacy decoding and concatenation, with excluded v0.4 rejection. Each CLI invocation uses the system loader and its own library. A mismatch rejects the gate. Preserve a failed attempt and diagnose it; do not reduce features to pass. This small native smoke suite is separate from, and does not replace, the full unchanged upstream build checks.

## Protocol v1 history and rejected native attempt

The original protocol timed stock/O2/O3 on both corpora at levels1/3/9 in all six three-variant permutations: **108 measured trials**, plus six fresh level9 calibration trials (all three variants on both corpora). Each variant occupied each position twice and each pair had 3:3 relative order. Projection was maximum calibration lifecycle cost × 108 × 1.15 against the remaining 300-second budget. This protocol remains historical, not the current execution plan.

The parent reports: initial macOS-tar transfer failed inventory due to AppleDouble extras; a second Python-tar transfer passed the complete native gate, including all formats, wrappers, legacy, dictionary and cross-decode. Attempt identity **`nativebench1`** then ran all six v1 calibration trials and rejected with `calibration rejects five-minute budget; retain, redesign explicitly` before any measured blocks. No throughput conclusion follows. Native absolute output paths, result hashes and raw logs must be supplied/retrieved by the parent; this sub-agent has not accessed them. Preserve that rejected attempt independently of v2. Its calibrations must never be selected or relabeled as measured observations.

## Protocol v2 history and rejection

V2 retained all-three-variant native correctness but timed only O2/O3: two corpora × levels1/3/9 × six balanced paired blocks = 72 measured invocations. Four fresh level9 calibration calls covered both variants and corpora. Projection used maximum calibration lifecycle cost × 72 × 1.15 against the remaining original 300-second budget. Parent reports source O2 5.966 s / O3 6.999 s and binary O2 14.502 s / O3 7.925 s, giving projection 1200.765 s versus 261.227 s remaining. The runner rejected before any measured blocks. These are calibration lifecycle costs, not throughput results; never relabel or pool them with v3. Full prior code, plan and available host evidence are preserved locally; native evidence retrieval remains parent-owned.

## Bounded benchmark: measurement protocol version 3

`bench` now requires exactly one `--corpus source.tar|stock-libzstd.elf` and one `--level 1|3|9`. Each invocation is a workload unit, with its own exclusive new output directory, results, gate linkage and observed context. The complete planned protocol remains **six units**, two inputs × three levels; a completed single unit does not establish a complete matrix. Never pool different corpora, levels, partial runs or calibration records. All six complete units in the same matched cohort are required for a full-matrix claim; report each unit separately even then.

A unit performs **two fresh calibration calls**, O2 then O3, on exactly the selected corpus and selected level, using `--single-thread -bLEVEL -i1`. It then performs **six balanced paired blocks**, AB, BA, AB, BA, AB, BA, with A=O2 and B=O3: twelve new measured calls, each variant occupying each position three times. Every call reports both compression and decode internal operation throughput. Stock remains context-only provenance and native correctness; only actual O2/O3 calls enter measurement. Page cache is warm by use, with no cache flush or cold-storage claim.

The original **300-second monotonic bound applies separately to each invocation**, including preflight, calibration, guards, cooling and all measured calls. Projection is **maximum of the two fresh same-workload calibration lifecycle costs × 12 × 1.15** against remaining time. Calibration is already elapsed and never counts as measurement. Projection or any health/provider/session guard failure still rejects and preserves the attempt. No automatic extension, reduction, feature removal or calibration reuse is authorized. Host checks establish no native feasibility.

The global full native gate still checks stock/O2/O3 with unchanged provenance and correctness coverage. **A fresh v3 gate is mandatory** because the runner hash changed; the successful v2 gate cannot authorize v3. One successful v3 gate can be reused across units only with the same runner, bundle, dependency providers/loader, boot and complete policy/session/package context. Each invocation verifies these fingerprints and drift guards. Use the same explicit `--expected-lock-state` for gate and every unit. The default remains `true`; the commands below show the parent's explicit unlocked cohort (`false`) without changing desktop state. Any context change requires a fresh complete gate and a distinct cohort, not relaxed checks.

Parent-only commands on the Pi, after authenticated transfer/hash verification, with actual absolute paths and a new result root. These are instructions only; this implementation session ran none of them. Retain full command outputs and raw evidence. Run serially under the parent's exclusive Pi window, with no concurrent CTS load or other measurements:

```bash
runner=/absolute/zstd-package-benchmark.py
bundle=/absolute/zstd-package-bundle
results=/absolute/new/zstd-protocol-v3
conditions='native 4GB Pi; explicit unlocked cohort; fixed output/cooling/supply; no competing load; existing schedutil; warm page cache; encrypted USB SSD'
python3 "$runner" gate --bundle "$bundle" --out "$results/gate-v3-1" --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions"
gate="$results/gate-v3-1/results.json"
python3 "$runner" bench --bundle "$bundle" --gate "$gate" --out "$results/source-level1-v3-1" --corpus source.tar --level 1 --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions"
python3 "$runner" bench --bundle "$bundle" --gate "$gate" --out "$results/source-level3-v3-1" --corpus source.tar --level 3 --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions"
python3 "$runner" bench --bundle "$bundle" --gate "$gate" --out "$results/source-level9-v3-1" --corpus source.tar --level 9 --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions"
python3 "$runner" bench --bundle "$bundle" --gate "$gate" --out "$results/elf-level1-v3-1" --corpus stock-libzstd.elf --level 1 --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions"
python3 "$runner" bench --bundle "$bundle" --gate "$gate" --out "$results/elf-level3-v3-1" --corpus stock-libzstd.elf --level 3 --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions"
python3 "$runner" bench --bundle "$bundle" --gate "$gate" --out "$results/elf-level9-v3-1" --corpus stock-libzstd.elf --level 9 --cpu 2 --exclusive-pi --expected-lock-state false --conditions "$conditions"
```

The parent creates the result root before these commands; each gate/unit leaf must be absent. A failed unit remains rejected: preserve and diagnose before another explicit attempt in a new directory. Report all six measured block values per unit with medians/ranges and paired O2/O3 differences. A full-matrix claim requires every unit; partial results cannot substitute for missing units. No benefit claim exists from this change.

## Stops, telemetry and interpretation

Before trials and after completion the runner rejects session/output, governor/min/max/driver, CPU-online, boot/kernel or package-version drift and rechecks provider/loader hashes. The observed changed context is retained on drift. Every trial starts at at most 52°C. Cooling consumes the same deadline. During a child, sampled native temperatures at **70°C or greater** or any native `in0_lcrit_alarm` other than exactly `0` stops the process group; missing sensors also stop. Requested cpufreq is only a policy snapshot. Firmware actual clocks, throttle history and energy are explicit null/unknown; native voltage alarms do not establish historical firmware throttle state. No CPU/GPU clock-time inference or energy-efficiency claim is valid.

Each child has a 25-second wall deadline, 20/21-second soft/hard CPU limit, 512 MiB virtual-address limit, 64 MiB per-file limit, sanitized environment, and one-CPU affinity. These bounds may expose a legitimate target/runtime requirement; such a failure is a rejected attempt, not a speed result. The small T2 correctness smoke can create two workers pinned to the same core; all performance trials remain single-thread. Stop paths kill the child process group and reap it. Ctrl-C, mismatches, deadlines and health stops preserve status and evidence. No cleanup discards temporary files or raw output; parent removes the private result tree only after evidence transfer/review. Sampling is finite and only active during this experiment, not an idle daemon.

Results format:

- `manifest.json` in the bundle records all input hashes, sizes, regular-file modes, symlink targets, public corpus origins and comparison labels.
- `results.json` records status/reason, runner/manifest/gate hashes, board/context, provider/loader fingerprints, explicit unknowns, calibration projection, every command and trial linkage. `measurement_protocol_version` explicitly identifies v3; benchmark `measurement_protocol` records the selected `workload_unit`, all six `full_matrix_units`, claim scope, variants, selected corpus/level, six balanced orders, counts, CLI, deadline, headroom and the complete unit schedule. `calibration.records` links each selected corpus/variant/level lifecycle cost to its trial index and raw command; calibration also identifies the workload unit, and projection records twelve new trials and 15% headroom. `trials` records actual phase/block/order through its ordered entries, including partial/rejected attempts. Trial `compression_MB_s` and `decode_MB_s` are actual CLI **internal algorithm** rates, decimal MB/s, parsed only from a complete matched-input rate pair. Compressed bytes are retained.
- `NNNN.stdout`, `NNNN.stderr` and optional `NNNN.stdin` preserve each raw command stream separately, including binary smoke inputs/outputs and rejected commands. Command records contain exact argv/environment, UTC start, exit/stop reason, lifecycle wall seconds, individual child user/system CPU seconds, maximum RSS in Linux KiB and context switches where completed. Wall includes loader/startup, corpus reads, I/O and bounded sampling wait; CPU includes the complete child process, not a pure algorithm counter. Do not divide corpus bytes by this wrapper wall and call it zstd's internal throughput. It is not a package-manager or disk benchmark.
- `health.jsonl` retains temperatures, native voltage alarms, requested frequencies, PSI, load and memory state including the sample triggering a safety stop. `tmp/` retains dictionaries and sample files. Review private paths/session metadata before publishing; no credentials are collected.

No statistical claim should survive a rejected/partial matrix. Preserve all calibration, failures and stops beside the successful run; never select only the fastest observations. Even a complete matrix establishes only this public corpus/levels/native 4GB Pi cohort and cannot justify a global O3 change, application latency claim, Raspberry Pi OS parity, or extrapolation to Pi 5/8GB boards.

## Preserved v2 local verification (historical)

Embedded host-only tests exercise real rate parsing (including wrong-size/zero/incomplete rejection), actual paired scheduling for every corpus/level, positional/pair order balance, reversed workload order, four calibration jobs and conservative 72-trial projection, hash mismatch rejection, foreign/missing loader-provider rejection using temporary files, and UTF-8 legacy text versus binary escaped fixture parsing. A focused test drives `Runner.bench` itself with native execution/health substituted to verify four calibration then 72 measured calls, original CLI shape and explicit v2 result metadata. Synthetic parsed rates in that orchestration test validate no performance behavior and execute no package code.

```bash
python3 tools/pi-experiments/zstd-package-benchmark.py self-test >build/local-zstd-protocol-v2-preserved/v2-self-test.log 2>&1
cat build/local-zstd-protocol-v2-preserved/v2-self-test.log
```

Six tests passed. Seven in-memory wrong-protocol mutations each failed the relevant tests: unbalanced 4AB/2BA blocks, restoring 108 stock-inclusive measured calls, projecting 108 instead of 72, subtracting calibration from fresh measured count, dropping 15% headroom, omitting O3 calibration, and substituting stock in actual measured dispatch. Full run output is retained in `build/local-zstd-protocol-v2-preserved/v2-self-test.log` and `v2-mutations.log`. Native ABI/loading, telemetry, full-feature correctness, calibration and performance still require the parent's fresh execution gates.

The ignored local preservation directory `build/local-zstd-protocol-v2-preserved/` retains the complete original runner (including all original embedded tests), original plan, all five available original `/tmp/zstd-package-benchmark*.log` files unchanged, and `preserved.json` with their hashes. The original runner SHA-256 is `d35d0f249c0017ca3792c961c10224e297ab77d8fd6f6dcd848b880c78d0bb1a`. The old four-test pass and original four red-mutation evidence remain intact; the order test is explicitly adapted for v2 rather than silently treating the old permutation protocol as current. Native raw run logs remain on the Pi and are not represented as locally archived. Parent retrieval must preserve them in full within the total artifact allowance.

## Explicit session cohort on restored connectivity

Parent reconnected at owner-provided192.168.1.52 using StrictHostKeyChecking and the previously trusted192.168.1.45 host-key alias; exact key identity passed. Kernel remains32.1. The first fresh v2 gate correctly rejected the unlocked desktop against its default locked expectation before timing. Instead of changing lock/DPMS/idle policy, the runner now accepts an explicit --expected-lock-state true|false, defaulttrue. It requires that exact initial state and still rejects any subsequent session/output/policy/provider drift. This keeps an unlocked cohort distinct from historical locked runs without changing desktop state.

Seven host tests pass after the change, including expected-state mismatch/missing-output rejection; an unconditional-acceptance mutant fails the focused guard test. Runner SHA25629e7e6a842a5be49c0b4d612c583176202a09c592b0328cc7a2a9e1ee0cc20ae requires another complete native gate. Parent's gate-v2-2 completed successfully; benchmark-v2-1 subsequently rejected during projection as recorded above. Raw native results remain parent-owned until retrieved/reviewed. V3 retains the five-minute bound per unit, all six planned workloads, six paired blocks per workload and all-three-variant native correctness.

## Protocol v3 host verification and preservation

Eight embedded host tests pass, including the parent's unchanged expected-lock-state guard test. Actual `Runner.bench` orchestration is exercised for all six selections with native execution/health substituted: exact selected corpus/level and `-i1` dispatch, two fresh calibrations then twelve measured calls, AB/BA repetitions, persisted schedule/unit/full-matrix metadata and max-cost × 12 × 1.15 projection. The normal `Runner.run` rejection boundary is exercised with an over-budget projection to verify two calibration records persist and no measurement dispatch occurs. Parser tests reject missing corpus/level and invalid choices before native preflight. Synthetic rates validate orchestration only and establish no performance behavior.

Eleven in-memory mutants fail the relevant tests: wrong corpus, wrong level, whole-matrix levels, both corpora, level9-only calibration, unbalanced repetitions, old 72-call projection, calibration reuse, omitted headroom, stock timing and unconditional session acceptance. Whole test outputs, including an initial test-fixture mode-field error and its corrected passing run, are retained under `build/local-zstd-protocol-v3-preserved/` in `v3-self-test-initial-fixture-error.log`, `v3-self-test.log` and `v3-mutations.log`; the reproducible host mutation driver is `check-mutations.py` there.

That new ignored directory preserves the exact parent runner SHA-256 `29e7e6a842a5be49c0b4d612c583176202a09c592b0328cc7a2a9e1ee0cc20ae`, the pre-edit plan, the prior v2 preservation directory and all available small local zstd test logs, indexed by `preserved.json`. The parent's seven-test green log and session-guard mutant log are copied unchanged into `parent-guard/`; `verification.json` records that the native gate, health, provider, session, child-bound and drift functions remain structurally unchanged. Existing v2 evidence paths remain unchanged. Total preservation/test artifacts are approximately 242 KB, below 2 MiB. No Pi/SSH, Docker, builds, native benchmarks, CTS/shared-ledger edits, staging, commits, messages or subagents were used. Parent retrieves the native evidence separately; this directory makes no claim to contain remote raw evidence.

```bash
python3 tools/pi-experiments/zstd-package-benchmark.py self-test >build/local-zstd-protocol-v3-preserved/v3-self-test.log 2>&1
cat build/local-zstd-protocol-v3-preserved/v3-self-test.log
```

V3 runner SHA-256: `bf40ba15e4eb370c35f8fc2a525dd87033748a0d4df27d457f72fbad6e365bf0`. A fresh matching native gate is required before any unit execution.
