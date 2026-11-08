# Pi implementation progress

## November 8, 2026 — reconciliation at 10:51 UTC

Lead owns every physical Pi operation and benchmark. Three independent GPT-6.1-Sol delegates use High reasoning and Normal speed: versioned measurement repair, primary-source audit, and Bluetooth candidate investigation. No delegate has physical access authority.

Repository heads: integration workspace b0a0b995eba9799757d04d4d16f7f54812eaaba5; upstream review a94119ebc; stable f8e6b769c; packages db4db989; ISO 38f368f. The four sibling trees were clean. Existing untracked kickoff and .morphess are preserved.

Live verified: Raspberry Pi 4 Model B Rev 1.5, big-endian revision bytes `00 c0 31 15`, MemTotal 3832948 KiB; kernel/headers 7.3-32.1; runtime/settings 4.5.0-2.2; picker release 1. Corrected package query: raspberrypi-4-support 1-1 is installed; raspberrypi-4-desktop is absent. The initial query used an incorrect support package name. `/tmp/omarchy-4.5-review/` disappeared across reboot: restaging and hash verification are required before any installation. Root is encrypted Btrfs on USB SSD; separate /boot is FAT. Public-update holds remain intact. No failed system or user services. UART serdev binds but Bluetooth has no usable controller. KPTI is confirmed active by current-boot kernel log; AUX and VPU clocks read 499999998 Hz. zram uses zstd. No boot/package/service changes made during reconciliation.

Existing authorized .env credential worked through password stdin to `sudo -S bash -c`, separate from script transport; no credential was printed or persisted in evidence. Snapshots 1–4 exist. Root-only ESP archives exist (189 MiB each); rollback is available but not rehearsed. Recovery media and unattended encrypted unlock are not yet established for a new reboot, so no reboot experiment has begun.

Raw private logs: `build/upstream-pi/stable-4.5/optimization/live-unprivileged.log` and `live-root.log`. These remain ignored because they contain machine identifiers. This tracked summary preserves sanitized results. Legacy metrics remain untouched and must not be used as a valid before/after series; repaired tools will establish a versioned boundary.

## Next integration gates

Review and run the repaired measurement tools; preserve sanitized v2 baseline with provenance. Integrate primary-source corrections in discovery/release ledgers. Validate the bounded Bluetooth candidate before selecting any physical test. Reconfirm recovery media and unlock availability before boot changes. Package/display candidates need restaging, hash verification and recovery backup before transaction; functional UI acceptance remains open. No performance improvement, Pi OS parity, energy result, 8GB qualification or release readiness is claimed.

## Source-tested candidate and recovery preparation

Package repository local commit `474cdba8` preserves an inactive serdev fail-fast patch plus a regression compiling the real v7.3 setup function. Parent test log `/tmp/omarchy-pi-bluetooth-parent.log` confirms pristine failure and patched success; it does not validate radio behavior. No full kernel build is warranted solely to claim this diagnostic change repairs Bluetooth.

The old ESP archive passed tar listing; SHA-256 `090fee8a52303b2ff4b7986271b688fa8e904bfa5e7389058db1b1ead4245b68`. Current firmware-card files were archived without modification; `/root/omarchy-pi-optimization-20261108/firmware-before.tar`, SHA-256 `497255616a66e0fa7488cdfdafdadc7b24ba7d266cc9d495852adf2569c98a81`. Matching runtime/settings 2.2 recovery archives were copied to `~/.cache/omarchy-optimization/recovery/` on the Pi (SHA-256 `a9cf17d20d93d9abd9781b174c8eb13906b9b5681a36e058d6f602c61e17856d`, `417498901542831b7ddf57f6d144b8d35af8c08098d05ad119e07092a30af280`). Five reviewed 2.4/support/picker candidates were verified against the existing manifest locally and restaged under `~/.cache/omarchy-optimization/candidate/`; all remote hashes match. Raw staging/recovery logs remain in the optimization evidence directory. Restaging is not installation.

A bounded CPUFreq ABBA experiment was started with `tools/pi-experiments/cpufreq-trial.py`: four SHA-256 workers, 20 seconds/trial, native voltage-alarm and 75°C health stop, pre-trial cooling threshold 48°C, restoration in finally and between trials. Governor is the only policy variable. It records requested cpufreq rather than claiming actual firmware clocks, and explicitly leaves firmware throttle/energy unknown. Results pending; no shipping governor change selected.

## CPUFreq screening result

Completed four trials and independently confirmed restoration to schedutil. Tracked sanitized raw results and limitations: `results/pi4-4gb-native/2026-11-08/`. No repeatable performance-governor benefit was demonstrated; retain schedutil. All sampled requested frequencies were 1.8 GHz; firmware clocks/throttle/energy remain unknown. Shared-session contention and unequal start temperatures limit causal claims. No positive efficiency gain is claimed.

Asked for recovery-media readiness and ability to unlock encrypted boot before future reboot/rollback tests; Kai received needs-input successfully. This is an input gate for boot work, not a request to reauthorize routine implementation. Non-boot/source work continues.


Recovery media and encrypted-unlock readiness were confirmed by Preetham before the next candidate transaction.

## Reviewed package installation and desktop checkpoint

Installed all five reviewed candidates using explicit pacman -U paths; no system upgrade/kernel replacement. Runtime/settings now 4.5.0-2.4, support/desktop 1-3, picker release 2. Root snapshot 5 plus current ESP/user-config backups completed first. Snapshot's asynchronous boot-history write caused the first tar attempt to fail; the next archive succeeded before installation. ESP SHA-256 f505e756521dcf4102ddfb1426eb0cadd605902d4ff72cea73a4cf70dcab36a1; user config SHA-256 2004b3c49980ecffc2d977214a7c366b9972fbeaad665651a0b98f801840ae1c. Socket entries were ignored normally. Matching previous runtime/settings archives remain staged. Root package-integrity checks report zero altered files for all five packages. Pi boot verification and health pass; Hyprland reports no config errors; no failed units.

Shell restart was initially refused while locked. Preetham unlocked the desktop; restart then succeeded. Parent inspected the resulting full-screen screenshot (private ignored desktop-installed.png): desktop and bar render, icons/text are present without apparent clipping/overlap. This is basic rendering evidence, not display preview/revert/persistence or capture playback acceptance. The session log reports a notifications placements binding-loop warning after restart; it is not yet attributed to this candidate. No new font/style change was made.

Versioned recorder physical transport now succeeds via explicit authorized password stdin framing, with root euid verified and credentials absent from argv/logs. Parent commit 47b323dc and 13 focused passing tests cover the added transport. Two sanitized v2 package-state samples are tracked separately; conditions differ and no causal performance claim is made from them. Initial failed framing attempt persisted no sample. Legacy six rows remain byte-preserved.

Supported NEON XTS software modules are packaged but initially unregistered; only xts-aes-lib priority 110 appeared. Screening loads registered xts-aes-neonbs priority 250, without changing the existing root mapping. The initial cryptsetup samples overlap desktop work and are unsuitable as a causal comparison. Both modules were successfully unloaded. A separate bounded AF_ALG generic-xts experiment is now isolating a single aes_neon_bs load with before/after/reversal and public test-key ciphertext equality checks. Direct AF_ALG driver-name binding failed before measurements; the runner now requests the generic algorithm and records module-registration state separately. No boot-policy/source-default change has been made for crypto.

## Reversed crypto candidates and display preview

Tracked crypto results/reproducer: results/pi4-4gb-native/2026-11-08/crypto/ and tools/pi-experiments/xts-algorithms.py (commit bd381639). Single-module generic-AF_ALG phases and reversal showed no useful benefit; both NEON modules were unloaded, confirmed absent from lsmod, and original throughput returned. Existing root mapping and persistent boot defaults were unchanged. Ciphertext hashes matched all phases. No storage-efficiency win is claimed.

Live display preview of scale 1.6 timed out and restored the original HDMI-A-1 state exactly (1024x768@60.004, scale 2, position 0,0, transform 0), with unchanged monitors.lua SHA-256 58989e90ef481e73401f3af77c76c79b1ef11e6f67e3e3dfce3e7b8bc16b2d31. Screenshot at three seconds showed a rendered bar but black background and no visible display panel; full visual acceptance therefore fails/pends investigation. Raw log and screenshot: optimization/display-preview-timeout.log and display-preview.png. The earlier desktop screenshot rendered wallpaper correctly. Timeout exit 1 is expected rejection behavior, not a failed restoration.

Controlled reboot requested after user-confirmed recovery media/unlock readiness and successful installed boot verification. No EEPROM/firmware, encryption, mitigation, kernel or persistent clock change was made. Post-reboot evidence pending. Full rollback rehearsal remains open.
