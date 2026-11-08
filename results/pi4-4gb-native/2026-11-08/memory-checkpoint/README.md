# Locked-desktop memory checkpoint

Parent ran the read-only low-level collector as root before browser calibration. This is one baseline observation, not a policy experiment or a performance result. No settings were changed. Full raw private snapshot remains under ignored optimization evidence; snapshot.json preserves sanitized memory/THP/zram counters and exact script hash.

Observed top-level THP `always`, 2 MiB subpolicy `inherit`, other exposed sizes `never`; defrag `madvise`, shmem `never`, swappiness 150, zswap disabled. MemAvailable 2,124,020 KiB; anonymous hugepages 888,832 KiB; CMA free 28,224 of 65,536 KiB. Memory PSI avg10 was zero. Existing zram payload remains small. Neither these facts nor free CMA establish a memory bottleneck, GPU exhaustion or a reason to tune. No browser, compositor or shell process attribution was collected.

Collection took approximately 57 ms, sequentially. Source provenance and proposed decision rules are in plans/omarchy-pi-low-level-next-experiments.md. Storage profiles remain unexecuted because fio/perf are absent. No 8GB/Pi 5 or energy inference.
