# H.264 quiescence source evidence

November 8, 2026. Read-only source research; new evidence written only here and in `plans/omarchy-pi-h264-quiescence-contract.md`. No builds, runtime tests, hardware access, existing-file mutations, staging, commits or external messages. The task's explicit no-messages restriction supersedes the general Kai reporting instruction; the parent retains reporting ownership.

Read the [contract report](../../../../plans/omarchy-pi-h264-quiescence-contract.md) for conclusions, scope and parent gates. Evidence is source-level; none demonstrates firmware execution or physical DMA cessation.

- `local-inputs.json`: SHA-256 of exact replayed-import-11 C/headers and Makefile, both candidate reference trees, provenance and task inputs. Historical paths are recorded explicitly; this audit does not modify or replay the series.
- `downloads.json`: exact primary URLs, local filenames and content SHA-256. Failed fetches remain recorded. The attempted downstream `vchiq_2835_arm.c` path returned 404; platform logic is in the fetched `vchiq_arm.c`. No missing file is treated as evidence of missing functionality.
- `primary/arch/` and `primary/drivers/staging/`: additions from the same downstream Linux commit as the existing candidate references, `2569533d6c33c15231fbc21704c87fcebc67173c`.
- `primary/linux-7.3/`: six targeted files read from the existing local Linux archive, not a new kernel checkout/build. Archive SHA-256 provenance comes from the existing pinned replay documentation; this audit did not independently rehash the entire archive. File content hashes are recorded.
- `primary/userland/`: VCSM-related C/headers discovered through the pinned repository tree, plus commit and tree responses. Supplemental revision `a54a0dbb2b8dcf9bafdddfc9a9374fb51d97e976` was resolved once from HEAD and then used by hash for file downloads.
- `primary/firmware/`: commit response and README at `ab5c7f86283ceb58b7adb269cae1d16092a31bf6`. No binary reverse engineering or claim that this is installed firmware.
- `source-excerpts.txt`: selected line-numbered implementation ranges for pending IMPORT, mapping retention, downstream cleanup, VCHIQ close/bulk abort and driver-core removal. These are excerpts, not a substitute for the complete hashed inputs.
- `negative-search.log`: full scoped `rg` output for `ACTION_CLEAN|action_clean|cancel|reset|quies|drain|RELEASED|suppress_bind_attrs`, case insensitive, C/headers only. Matching comments and unrelated resets were inspected as context, not counted as contracts.

Additional web search scope: three queries restricted in their query text to raspberrypi GitHub sources, for ACTION_CLEAN; BCM_VC_SM_CMA module/VCHIQ configuration; and VCHIQ reset/firmware/close. Results were unrelated issue logs and supplied no usable protocol contract. Direct pinned primary files above supply the findings. Search absence is not proof of absence in private firmware or all source history.

The bounded negative result is no implemented/import-specific cancellation acknowledgement or all-VCSM-DMA close/reset guarantee in this inspected source set. RELEASED is the explicit allocation-completion event; a timeout, transport close or host join is not interchangeable with it. Normal responsive runtime experiments remain a separate parent decision after build/lifetime/recovery gates.
