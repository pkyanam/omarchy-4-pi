# Legacy v1 evidence, excluded from protocol v2

`pi4-v1.csv` preserves all six original rows and their numeric strings from `build/upstream-pi/stable-4.5/pi4-metrics.csv`. It contains no credentials, hostname or serial; no private `.env`, remote logs or machine dumps were copied. SHA-256: `5ee8e0fa6bac40c9cf23842bdb8a99f829f7c1898ad8487c98df212eb0178322`. The original schema is retained solely for historical audit. No values were retroactively “fixed” into invented measurements.

These rows are **unverified legacy observations**, not a corrected baseline. Their recorder could consume the first script line as a password and failed to execute the later probe as root; the exact path used to produce these rows is not established. Labels were printed but never persisted. The claimed noise floor in the old METRICS document is not a controlled noise study; timestamps are not 12 seconds apart and load/thermal state was not controlled.

Known limitations apply to all six rows:

- `1531c000` is the native-endian rendering of DT bytes `00 c0 31 15`, not a canonical board revision. The project ledger identifies the board as Pi 4 Rev 1.5, revision `c03115`, 4GB; that is external context, not repaired row evidence. `model_gb=4` came from a default and does not independently identify RAM.
- `throttle_flag=-1` conflates nonzero status and missing/failed access. Neither current nor historical throttle bits can be recovered.
- `aes_accel` attempted module insertion and is not a read-only capability measurement. `ce_crypto_entries` counts registrations, not CPU instructions or OpenSSL acceleration. `midr` is actually a CPU part string.
- `pti_enabled` is an invalid cmdline/KASLR inference. `meltdown_affected=0` does not establish KPTI runtime state. `lto_enabled` and `hz` may come from other installed kernel configs; missing LTO config could be reported as enabled.
- `march` describes local makepkg settings, not how installed packages were built. The syscall columns include Python overhead; the null loop and open target differ from v2.
- AES-CBC and SHA-256 used differing default buffer selections. Human-readable OpenSSL `k` is decimal thousands of bytes/s; division by 1024 did not yield MiB/s. Failures could become zero. These fields are neither XTS nor storage throughput.
- Temperature and clocks were single snapshots, privilege and zone identity were not validated, and absent values could become zeros. Zram/video fields do not establish encryption or codec usability.

Do not feed this file to the v2 validator or mix it with v2 distributions. The old SVG is intentionally not copied: its security-state scoring and first-to-last improvement coloring are not defensible evidence. The original three scripts were read and remain untouched in the ignored build tree.
