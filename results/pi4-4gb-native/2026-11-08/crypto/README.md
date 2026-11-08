# Supported software XTS screening

Status: measured and reversed; no persistent module/initramfs change selected. Existing root transform was not replaced. No storage, browser or desktop throughput claim.

Exact matching kernel/headers: 7.3-32.1. Initially xts-aes-lib priority 110 was the only registered AES-XTS driver. Packaged aes_neon_bs and aes_neon_blk loaded successfully using existing ASIMD support, without forcing CPU feature bits. Both were then unloaded successfully, in separate steps. Three 3-second runs per phase request generic xts(aes) through AF_ALG with a public 512-bit fixture key and 64KiB blocks. Single-variable phases: original; only aes_neon_bs (priority 250); only aes_neon_blk (priority 200); restored original. The same ciphertext SHA-256 appears in all phases. Requested algorithm selection follows kernel registration priorities; this is not introspection of an already-open dm-crypt mapping.

Observed MiB/s (all trials retained):

| Phase | Trial 1 | Trial 2 | Trial 3 |
| --- | --- | --- | --- |
| Original | 81.47 | 80.45 | 80.70 |
| Bitsliced NEON | 78.72 | 77.62 | 77.89 |
| NEON block | 80.66 | 80.84 | 80.54 |
| Restored | 81.44 | 80.47 | 80.89 |

No useful repeatable gain was demonstrated. The original implementation must not be assumed scalar merely from its name. Keep existing boot policy. Test data stays in memory; no encryption/key/sector/security settings changed. The runner records CPU time and sampled temperature/native voltage alarm; firmware clocks/throttle and energy are unknown. Short sequential trials on a shared desktop are a screening result, not statistical release certification. A real encrypted-file/application test is justified only for a candidate with evidence of benefit.

Rejected attempts: initial cryptsetup before/after screen overlapped shell work and is not a causal result; direct AF_ALG binding by driver-specific name failed before measurements. The final reproducer requests generic xts(aes), and preserves cross-phase ciphertext equality. Raw rejected logs remain ignored in build/upstream-pi/stable-4.5/optimization/. The tracked reproducer is tools/pi-experiments/xts-algorithms.py. No hardware crypto support, Pi OS parity, 8GB/Pi 5 behavior or root-storage improvement is inferred.
