# Source-tested bounded workload units

Protocol3 partitions the fullmatrix into six independently bounded complete workload units, each with fresh O2/O3 calibration and six balanced paired blocks. The300s bound and allthree-variant nativecorrectness/health/context/provider guards are unchanged. Eight hosttests pass and eleven wrongprotocolmutants fail. No nativeperformance result follows from these host tests. Nativegate and eachcompleteunit must pass separately; rejected/partial units cannot be pooled. See plans/omarchy-pi-zstd-package-benchmark.md. Full originalv2 source/test/plan evidence is retained here.

## First native execution

The fresh protocol3 correctness gate passed on the designated4GB board. The first source/level1 unit remained at the52°C cool-start gate with no completed calibration or measured trials. Parent observed competing Node/npm/Codex CPU work and sent SIGTERM only to this experiment's runner; the sequence stopped and retained rejected evidence. No other process, service, package, lock or idle policy was changed. A quiet Pi window is needed for timing. native-summary.json records actual statuses, temperature/voltage observations and hashes of complete raw result files retained on thePi. No performance result is claimed.
