# Independent review of the matched full-package zstd results

Reviewed 2026-11-08. Verdict: accept the six completed v3 workload units as descriptive evidence that this matched O3 package decodes these two inputs faster than the matched O2 package on this native 4GB Pi cohort. Compression is mixed, with negative level-9 medians. Keep O3 as a package-specific follow-up candidate; these measurements do not justify installation or a shipping default.

## Evidence and independent checks

Read repository `AGENTS.md`, `plans/omarchy-pi-optimization-kickoff.md`, `plans/omarchy-pi-zstd-package-benchmark.md` and the complete runner through its execution/rejection boundary. Reviewed `results/pi4-4gb-native/2026-11-08/zstd-full-package-pair/summary.json`, all six `results-sanitized.json` files, all 84 calibration/measured stdout/stderr pairs and all six gzipped health logs. Opened the private archive in memory, without extracting it: `build/upstream-pi/stable-4.5/optimization/zstd-native-matrix-v3-2.tar.gz`, 379623 bytes, SHA-256 `df9359732afaea96528ec704c513c4d2711dadf34498d2630a0068ec1e301307`. It contains 2172 members totaling 13732113 uncompressed bytes. No private boot/session identifier is reproduced here.

The host-only audit independently extracted the final complete CLI input/compressed-size/rate row, checked it against the trial record, and also evaluated only the runner's `parse_rates` function from its AST. No runner initialization or package code executed. Raw streams in the sanitized tree matched their private archive bytes. Every private results.json and decompressed health log matched the summary's recorded SHA-256. No rate was computed from wrapper wall time. In these streams the complete rate rows are in stdout; stderr was also checked. Calling them raw stderr rates alone would misdescribe this capture.

All six expected corpus/level combinations are complete, each with exactly two calibration calls followed by twelve measured calls: **72 measured invocations plus 12 excluded calibrations**. Each invocation supplies both compression and decode rates, not two independently randomized observations. Each unit has blocks 0–5 in AB, BA, AB, BA, AB, BA order (A=O2, B=O3), one observation per variant per block. Both variants occupy each position three times. Actual measured argv uses its own package CLI/library via the system loader, `--single-thread -bLEVEL -i1`, and the selected corpus. All commands in the six units exited as expected with no stop record; calibration projections recompute as max(fresh lifecycle costs) × 12 × 1.15 and fit the remaining unit budget. Health spans are 62–113 seconds and recorded unit UTC durations are 63–115 seconds, below the separate 300-second bounds.

The raw private records, including unredacted boot IDs, agree across all six units for runner, manifest, gate, context, provider and loader fields. Runner SHA-256 is `bf40ba15e4eb370c35f8fc2a525dd87033748a0d4df27d457f72fbad6e365bf0`, manifest `005287346f79e751ffc179a178211fd515a5e5a8969eea027c7b83dc870809a2`, and gate `693c4f811001c9c7535af3e41ade6600901514a3e698d258acf990033c61af84`. This checks boot equality rather than equality of redaction placeholders. Recorded board is Pi 4 Model B Rev 1.5, revision c03115; CPU affinity is CPU2. Context is kernel `7.3.0-32.1-omarchy`, online CPUs 0–3, schedutil/cpufreq-dt policy 600–1800 MHz, explicit unlocked desktop, HDMI-A-1 at 1024×768/60.004 Hz, scale 2, DPMS on, and identical zstd/glibc/zlib/xz/lz4 versions. Repeated lock, monitor and package-query raw outputs match each unit's context. Loader traces for zstd and pzstd resolve libzstd into the corresponding stock/O2/O3 extracted tree; recorded provider hashes agree across units. Actual loader path/hash is `/usr/lib/ld-linux-aarch64.so.1` / `b1f2738bdb51e6419d7062f96c8a44bd68853698dc5ac624fa6ca9f9b03d456d`.

**Gate evidence limitation:** the supplied v3-2 private archive contains only the six benchmark units. The fresh complete v3 gate is reported in `results/pi4-4gb-native/2026-11-08/zstd-protocol-v3/native-summary.json` and its local success log, with the same gate hash and runner. The runner rejects unless that gate is complete and runner/manifest/context/providers/loader match; completed units are consistent with those checks having passed. However, the raw v3 gate results/streams/health were not present in the supplied archive or the inspected local v3 evidence. I could not independently compare the gate's private boot/context or replay its full correctness assertions from those raw outputs. Preserve/retrieve that existing gate evidence before claiming a fully independently audited native correctness gate. This is an evidence-completeness objection, not a missing measured workload or a request to rerun a benchmark.

## Recomputed effects

For each block, effect = 100 × (O3 rate / O2 rate − 1); the reported center is the median of the six paired percentages, not a ratio of medians. MB/s is decimal MB/s from zstd's internal in-memory algorithm timing. The following values agree with summary.json to floating-point precision. Ranges are observed extrema, not confidence intervals.

| Input / level | Compression paired median [range], % | Decode paired median [range], % | Equal compressed bytes, O2 and O3 |
| --- | --- | --- | --- |
| source.tar / 1 | +2.76 [+1.05, +3.73] | +6.64 [+4.63, +10.69] | 2447901 |
| source.tar / 3 | +1.10 [-0.22, +2.01] | +8.83 [+6.59, +12.68] | 2264833 |
| source.tar / 9 | -2.15 [-3.68, +0.00] | +7.80 [+7.60, +12.54] | 2020265 |
| stock-libzstd.elf / 1 | +3.95 [+2.95, +7.00] | +8.00 [+5.06, +11.52] | 393763 |
| stock-libzstd.elf / 3 | +2.34 [-4.85, +4.23] | +7.29 [+2.15, +10.45] | 366981 |
| stock-libzstd.elf / 9 | -1.11 [-3.70, +1.52] | +8.08 [+7.71, +10.21] | 354926 |

All 36 decode pairs favor O3. Source level-9 compression has five negative pairs and one tie; ELF level-9 has four negative and two positive pairs. Equal compressed byte counts hold for every measured trial, and for the calibration calls as well. This establishes equal reported compressed size for these inputs/settings, not bit-identical encoded frames or equality on unseen inputs; benchmark streams contain size/rates rather than saved benchmark frames.

### All six measured values per variant and paired effects

Vectors are in block order 0–5, with calibrations excluded. Each row gives O2 rates, O3 rates, then paired O3 effects (%).

- **source.tar, level 1**
  - Compression: O2 `133.4, 133.1, 134.2, 134.1, 133.9, 134.0`; O3 `134.9, 134.5, 138.3, 139.1, 137.7, 137.6`; effects `+1.1244, +1.0518, +3.0551, +3.7286, +2.8379, +2.6866`.
  - Decode: O2 `463.8, 459.7, 458.4, 468.6, 467.4, 451.9`; O3 `489.2, 496.9, 491.2, 490.3, 496.0, 500.2`; effects `+5.4765, +8.0922, +7.1553, +4.6308, +6.1190, +10.6882`.
- **source.tar, level 3**
  - Compression: O2 `45.0, 45.3, 44.7, 46.1, 44.8, 45.7`; O3 `45.8, 45.7, 44.6, 46.3, 45.7, 46.3`; effects `+1.7778, +0.8830, -0.2237, +0.4338, +2.0089, +1.3129`.
  - Decode: O2 `379.1, 379.4, 383.6, 384.0, 370.0, 377.3`; O3 `404.1, 416.9, 410.2, 416.6, 416.9, 411.9`; effects `+6.5946, +9.8840, +6.9343, +8.4896, +12.6757, +9.1704`.
- **source.tar, level 9**
  - Compression: O2 `16.4, 15.8, 16.4, 16.3, 16.0, 16.2`; O3 `15.9, 15.7, 16.1, 15.7, 16.0, 15.8`; effects `-3.0488, -0.6329, -1.8293, -3.6810, +0.0000, -2.4691`.
  - Decode: O2 `381.1, 391.6, 396.8, 398.7, 398.9, 393.5`; O3 `428.9, 434.9, 428.1, 429.1, 429.7, 423.4`; effects `+12.5426, +11.0572, +7.8881, +7.6248, +7.7212, +7.5985`.
- **stock-libzstd.elf, level 1**
  - Compression: O2 `105.2, 106.2, 106.2, 105.7, 105.9, 106.2`; O3 `108.3, 110.2, 110.6, 113.1, 110.4, 110.0`; effects `+2.9468, +3.7665, +4.1431, +7.0009, +4.2493, +3.5782`.
  - Decode: O2 `374.9, 379.2, 380.8, 373.6, 362.8, 367.2`; O3 `400.3, 398.4, 400.7, 408.1, 404.6, 404.1`; effects `+6.7751, +5.0633, +5.2258, +9.2345, +11.5215, +10.0490`.
- **stock-libzstd.elf, level 3**
  - Compression: O2 `26.8, 26.7, 26.0, 25.4, 25.8, 25.9`; O3 `25.5, 26.8, 27.1, 25.9, 26.6, 26.6`; effects `-4.8507, +0.3745, +4.2308, +1.9685, +3.1008, +2.7027`.
  - Decode: O2 `322.5, 336.5, 339.6, 333.1, 333.1, 336.2`; O3 `356.2, 361.5, 346.9, 359.9, 356.9, 356.0`; effects `+10.4496, +7.4294, +2.1496, +8.0456, +7.1450, +5.8894`.
- **stock-libzstd.elf, level 9**
  - Compression: O2 `13.5, 13.2, 13.3, 13.6, 13.6, 13.4`; O3 `13.0, 13.4, 13.2, 13.4, 13.7, 13.2`; effects `-3.7037, +1.5152, -0.7519, -1.4706, +0.7353, -1.4925`.
  - Decode: O2 `346.3, 344.2, 342.5, 339.1, 338.3, 341.9`; O3 `373.0, 371.8, 370.2, 366.5, 372.4, 376.8`; effects `+7.7101, +8.0186, +8.0876, +8.0802, +10.0798, +10.2077`.

## Health and memory scope

The runner waits for a sampled maximum temperature ≤52°C before each calibration/measured call, then rechecks stable context. It rejects sampled temperatures ≥70°C, nonzero or missing native voltage alarms, missing temperature sensors, and deadlines; offending samples are written first. The cool-start check precedes another stable/context check, so it is a sampled admission threshold, not continuous proof of temperature at the exact process-launch instant. Health rows have monotonic timestamps but no trial ID or recorded monotonic child start; they do not independently establish a precise launch-temperature value per trial. No exact firmware clock or firmware throttle-history measurement exists.

The 4818 retained health samples all contain temperature and native voltage-alarm readings; every alarm is exactly `0`. Temperature extrema independently match the summary. No sampled thermal/voltage stop is hidden in these successful units.

| Unit | Samples | Sampled temperature °C | Measured O2 max RSS range, KiB | Measured O3 max RSS range, KiB |
| --- | --- | --- | --- | --- |
| source.tar / 1 | 854 | 50.147–55.504 | 28728–28796 | 28876–30672 |
| source.tar / 3 | 853 | 51.121–55.504 | 29448–29532 | 29612–29676 |
| source.tar / 9 | 893 | 50.634–55.504 | 39156–41200 | 39432–39496 |
| stock-libzstd.elf / 1 | 696 | 50.634–54.530 | 18696–18828 | 18716–18816 |
| stock-libzstd.elf / 3 | 677 | 50.634–55.017 | 18564–18688 | 18584–18684 |
| stock-libzstd.elf / 9 | 845 | 50.634–54.530 | 18452–18584 | 18476–18568 |

RSS is the Linux wait4 child-process high-water mark for the combined compression/decode benchmark lifecycle, including runtime/loader and corpus/workspace mappings. It is neither library-only memory nor a separate decoder maximum, and it does not measure system-wide pressure or steady-state application memory. The fork/preexec launch may also carry the parent's pre-exec resident high-water footprint. The variation and near-baseline ELF results do not establish a useful memory improvement. The 512 MiB virtual-address limit is a safety bound, not measured RSS. Likewise child wall/CPU times include loader/startup/I/O and monitoring effects; corpus bytes divided by wrapper wall would not recover algorithm throughput.

## Package identity and tradeoffs

Checked the existing `attempt-3072m-swap0` extracted CLI/library sizes and SHA-256 values against the runner and completed-package transfer manifest. O2 libzstd is 854120 bytes; O3 is 1181800 bytes: +327680 bytes = **320 KiB, +38.36%** on-disk library growth (327680 / 854120 × 100 = 38.3646326%; the proposed 38.37% is a rounding error). This is not a 320 KiB proven RSS increase. Both CLIs are 267632 bytes but their hashes differ (`28a39030…` versus `959aefe8…`); equal CLI length is not byte identity. These are whole-package comparisons, not proof that only the shared library's machine code causes the speed difference.

Existing pair audit records and audit source check 87 compiler invocations per variant and 10 links, portable `-march=armv8-a`, the same toolchain/source/dependencies, shared/full format/legacy/dictionary/multithread/contrib/test features, and hardening including FORTIFY_SOURCE=3, stack/stack-clash protection, PIE, RELRO/NOW and nonexecutable stack. I independently compared the private build audit's normalized compiler, link and CMake-cache files: each pair is byte-identical after optimization/path normalization. No CPU tuning, LTO, PGO or fast-math variable is introduced. Both unchanged upstream check records passed; those build-host timings are not Pi measurements. The native runner additionally requires successful target loading/version execution, including candidate DT_RELR requirements. The smoke gate complements upstream checks; it is not exhaustive application ABI testing.

## Rejections and inference limits

Earlier attempts remain separate and contribute zero measured observations here. The retained attempt summary records initial AppleDouble/inventory rejection; v1's six calibrations followed by budget rejection; the first v2 gate's locked-state mismatch; and v2's four calibrations followed by budget rejection. The first v3 source/level-1 unit was terminated with signal 15 while waiting to cool, with zero completed calibration or measured calls (reported maximum 67.679°C, not a ≥70°C safety stop). The parent observed competing Node/npm/Codex work then; the later quiet-window check records 51.121°C before the successful sequence. No failure or calibration has been relabeled as a successful measurement. The earlier rejected v3 raw evidence, like the raw v3 gate, is currently represented locally by its summary/hash and log rather than in the supplied v3-2 archive; retain its full evidence as well.

AB/BA position balance reduces simple order bias but does not remove serial correlation or thermal/cache/frequency effects. Alternation is deterministic, all calibrations are O2 then O3, and entire workload units run serially source levels 1/3/9 then ELF levels 1/3/9. One board/session, six short `-i1` observations per variant, and narrow fixed inputs do not establish sustained behavior or population uncertainty. The desktop remains active; an exclusive lease and one process-list snapshot cannot prove no transient competitor throughout every call. Warm-cache internal algorithm rates do not establish package-manager time, cold encrypted-storage performance, browser/desktop latency or end-to-end decode speedup. Compression and decode in the same benchmark are coupled to that variant's encoder output.

Requested cpufreq samples/policies are not actual firmware clock measurements; all-zero sampled native voltage alarms do not prove absent firmware throttling or past undervoltage. Energy and power remain unknown. Stock was checked for provenance/correctness but **not measured**, and its historical compiler flags remain unknown: no gain versus installed stock can be inferred. There is no O0 comparison, Raspberry Pi OS parity result, Pi 5 claim, 8GB extrapolation or justification for global O3/default-flag promotion.

## Recommendation

Retain both candidates and this complete measured matrix. First complete the evidence archive with the existing raw v3 gate and rejected v3 attempt; no rebuild or new timing is needed for that. Treat the present decode advantage as a credible reason for a bounded package-specific follow-up, with the level-9 compression loss and larger library included in the decision.

For the next authorized measurement window, use the same authenticated packages and fresh matched gate in a separate cohort, reverse the unit sequence and start BA, and compare representative saved-frame decode plus a real package extraction operation with repeated wall/CPU/RSS measurements. Use longer bounded decode samples to test persistence, with explicitly budgeted cooling and no competing work; collect actual clocks/throttle state only through a validated available interface, leaving them unknown otherwise. Keep compression levels 1/3/9 and report regressions, not a pooled winner. A measured stock lane would be a separate contextual baseline with unknown historical flags, never a replacement for the O2/O3 control. Promote at most this zstd package after application/dependency ABI, install/rollback and representative workload checks pass and its tradeoff is acceptable; no global compiler change is supported.

Review actions were tiny host-only parsing, hashing and reads. The only new artifact is this document (well below 20 MB); no source/results/shared-ledger edits, Pi/SSH/Docker, compiler/build/benchmark, staging/commit, messages or subagents were used. Charts, ledger integration and the continuing exact-ABI CTS lane remain parent-owned.

## Parent evidence retrieval after this review

The parent subsequently retrieved the complete original v3 gate and rejected-v3 interruption archive, verified both results.json hashes against the previously recorded native-summary.json, and checked every expected gate command exit. Receipt: results/pi4-4gb-native/2026-11-08/zstd-full-package-pair/native-gate-retrieval.json. The raw archive remains private and preserves unredacted original evidence. This resolves local availability; it does not imply an additional independent reviewer recheck. The calculations and promotion limits above are unchanged.
