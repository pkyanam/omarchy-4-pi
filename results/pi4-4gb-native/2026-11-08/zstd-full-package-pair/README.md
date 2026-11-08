# Full-package matched compiler experiment

All six complete workload units passed on the native4GB Pi4: 72 measured invocations and12 excluded calibration calls. Each corpus/level has six paired O2/O3 blocks, balanced AB/BA. Runner, gate, boot/session/output/policy context, dependency-provider fingerprints and loader matched across units. Both candidates use identical full features, portable armv8-a ISA and hardening; only optimization level differs. Stock was correctness-tested, not timed; its historical flags remain unknown.

| Input | Level | O2 compression MB/s | O3 compression MB/s | Paired compression change | O2 decode MB/s | O3 decode MB/s | Paired decode change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| source.tar | 1 | 133.9 | 137.6 | +2.76% | 461.8 | 493.6 | +6.64% |
| source.tar | 3 | 45.1 | 45.8 | +1.10% | 379.2 | 414.2 | +8.83% |
| source.tar | 9 | 16.2 | 15.9 | -2.15% | 395.1 | 429.0 | +7.80% |
| stock-libzstd.elf | 1 | 106.1 | 110.3 | +3.95% | 374.2 | 402.4 | +8.00% |
| stock-libzstd.elf | 3 | 25.9 | 26.6 | +2.34% | 334.6 | 356.5 | +7.29% |
| stock-libzstd.elf | 9 | 13.4 | 13.3 | -1.11% | 342.2 | 372.1 | +8.08% |

Values are CLI internal algorithm throughput medians, decimal MB/s. Paired changes are medians of blockwise O3/O2 differences, not ratios of the two displayed medians. summary.json retains every paired difference and observed range; raw calibration/measured streams, sanitized complete results and losslessly compressed raw health evidence are tracked. Original complete raw archive is retained privately at build/upstream-pi/stable-4.5/optimization/zstd-native-matrix-v3-2.tar.gz with its hash in summary.json. Machine/session identifiers are redacted only in exported result metadata.

Decode improved in every paired block for these inputs, with workload paired medians6.64–8.83%. Compression is mixed: level9 paired medians regress2.15% on source and1.11% on ELF. Compressed byte counts match in all blocks/variants. O3 library grows from854120 to1181800bytes, +327680bytes/320KiB/+38.36%; CLI file sizes are unchanged. Native temperature spans50.147–55.504°C and sampled voltage alarms are allzero. Actual firmware clocks/throttle history, energy and application/desktop impact remain unknown. Short-i1 trials on one board do not establish a global compiler default, stock-package gain, PiOS parity, sustained-workload gain or8GB/Pi5 results. No package was installed.

The narrower causal conclusion is an O3 decode benefit for these full-package workloads, with compression/size costs. Keep the candidate experimental pending independent result review and a representative package/update workload before any promotion. Prior rejected calibration, interrupted cooling and first-transfer failures remain preserved separately; none is pooled here.
