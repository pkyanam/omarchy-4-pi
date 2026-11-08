# Inactive CTS kernel/package candidate — 2026-11-08

Prepared by the implementation lane using Sol/High in the assigned workspace. This is a concrete source/package candidate, **not built, installed, staged or boot-qualified**. Docker restart/RAM selection and the heavy-build lease remain with the parent. No Docker, compiler, module/kernel build, Pi/SSH, host package installation, active recipe edit, commit, PR, Kai message or subagent was used. Only this document and ignored `build/upstream-pi/stable-4.5/cts-kernel-candidate/` are owned here.

## Inputs and delivered files

Read root AGENTS, optimization kickoff, CTS backport decision/README, production test implementation/provenance and saved logs, reviewed kernel manifest/recipe/config/build/verification inputs, sibling README and owning kernel/support recipes. The sibling has no AGENTS.md or other discovered nested AGENTS.md; its head is `474cdba825e630250f9b82b8b0055b5ecb594da3` and its worktree was clean. The saved reviewed kernel lineage is `db4db9894ddc11838724928846b134699a6108b3` with the sole original local release override to 32.1; it is deliberately the starting point rather than a newer unrelated recipe. All saved recipe files except PKGBUILD remain byte-identical.

Candidate directory contains:

- `kernel/`: complete inactive owning recipe, all original patches/signatures/keys/hardware IDs/config, new `9000-serial-8250-bcm2835aux-hardware-flow.patch`, both SHA256 and BLAKE2 entries. `kernel-from-reviewed.patch` shows the complete recipe delta.
- `firmware/`: inactive `raspberrypi-4-pftf-cts` recipe, AUX-only overlay source, baseline and candidate config, pinned media manifest, ALPM hooks and explicit UUID/mount guarded synchronizer. No firmware executable is repackaged.
- `build-offline.sh`, `build-inside.sh`, `verify-packages.sh`, `verify-fdt.py`, `package-owners.sh`: bounded future build and archive checks. These are reviewable inputs; none was used to claim a package build.
- `manifest.json`, `INPUTS.sha256`, `logs/static-check.log`, `logs/archive-driver-replay.log`, `source-check/`: provenance and completed static validation. `current.fdt` is captured evidence, never a DTB to deploy.

Expected future artifacts are `linux-omarchy-7.3-32.2-aarch64.pkg.tar.zst`, `linux-omarchy-headers-7.3-32.2-aarch64.pkg.tar.zst`, the recipe's normal `linux-omarchy-nvidia-open-7.3-32.2-aarch64.pkg.tar.zst`, and `raspberrypi-4-pftf-cts-1-1-aarch64.pkg.tar.zst`. Kernel release must be `7.3.0-32.2-omarchy`. Header/NVIDIA dependencies remain exactly `linux-omarchy=7.3-32.2`, with the existing NVIDIA version/signing behavior. The Pi does not need NVIDIA installed, but the normal split recipe still builds and verifies it. Artifact sizes/hashes and package payload results remain pending real builds.

## Source checks and retained boundaries

Upstream driver commit is `ca576923c39863ac528427b563ea2f6631703d22`, patch SHA256 `3d863fb62041f38ffd3f8428da69698053f6dae77a42bef03aac0633f0685c18`. Extracted the original driver directly from the complete cached `build/upstream-pi/linux-7.3.tar.xz` (SHA256 `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`), applied the exact patch with zero fuzz/no offset and verified output `2ae07906f5415ceec9e4cac92a0d2f503e3e28150f0f3cdf8115087b34df6fb1`. No semantic adaptation. The complete original patch sequence is retained and will still be replayed by makepkg; it has not been recompiled or fully replayed here. A final driver-hash guard catches interference from any earlier patch.

Target `config.aarch64` remains SHA256 `41f89661b0af2c747e122f36417be7da2e7fb69049817c00404acf35fbef47a4`. `olddefconfig` must produce exactly that config, and release must match exactly, otherwise prepare fails. The only build policy delta replaces the recipe's nproc expansion with two jobs. Existing compressed DWARF flags from the successful reviewed build remain. No H264 patches, VCHIQ experiments, software XTS, CPU tuning, mitigation, LSM, signature or compiler optimization change is included.

Static checks passed: all preserved recipe bytes, native shell/Python syntax, source/checksum array lengths, all local SHA256 source entries and exact archive driver replay. Saved production tests are `bt-cts-backport-candidate/test-4/test.log`: 62 patched checks pass; unchanged production code compiles and fails 30. This lane did not rerun those compiler tests. Full archive ownership, capability, DTB, module vermagic, matching headers, NVIDIA, BTF/DWARF and firmware-overlay checks are prepared for real build output, not reported as passed.

## Firmware ownership and supported application stage

The actual saved firmware-card config (`build/upstream-pi/firmware-card-8gb/firmware/config.txt`) selects `armstub=RPI_EFI.fd`, fixed DT placement, `dtoverlay=miniuart-bt`, `dtoverlay=upstream-pi4`, then the physically proven `dtoverlay=omarchy-pi4-mainline-dma`. Saved HDMI diagnostic evidence records offline property comparison and a successful physical DMA-overlay boot. This establishes the existing early Raspberry Pi firmware config.txt overlay stage, before PFTF hands its DT to the normal UEFI → SSD Limine/UKI path. The new line appends `dtoverlay=omarchy-pi4-aux-rtscts` after those overlays. It adds only `/soc/serial@7e215040/uart-has-rtscts`, leaving DMA and routing intact. Future offline overlay comparison must confirm exactly that addition. Actual final boot FDT remains a parent gate; a source-stage check alone cannot prove firmware application.

`raspberrypi-4-support` 1-3 owns installed-system checks and SSD ESP/UKI verification. Its README explicitly excludes the separately prepared UEFI media; neither setup nor update-verify synchronizes it. `firmware-raspberrypi` in the saved archive supplies `/usr/lib/firmware/updates/brcm` radio files, not PFTF/config.txt/early overlays. Putting this overlay there or in `/boot/dtbs/linux-omarchy` cannot fix the captured PFTF-provided AUX route. Embedding a whole captured FDT into the UKI would also change ownership/boot assumptions and is excluded.

The inactive companion package addresses that exact gap. It owns payload and ALPM hooks on the root filesystem and synchronizes only its own overlay plus the reviewed config delta onto an explicitly configured firmware card. It depends on the exact candidate kernel and existing support package; no replacement bootloader, EEPROM flash, firmware executable edit, boot-order change, or manual register change is used. It is deliberately narrow to this reviewed PFTF route and saved media lineage. The saved most recent `optimization/current-RPI_EFI.fd` hash supersedes the older preparation hash because firmware variables changed. Any mismatch against the saved media baseline fails closed and requires parent capture/review of the actual media before revising candidate inputs.

Parent must provide root-owned mode 0644 or tighter `/etc/omarchy/pi4-cts-media.json`, for example `{"mount":"/mnt/omarchy-pftf","uuid":"ACTUAL-FAT-UUID"}`. Use the actual dedicated FAT mount and UUID; `/`, `/boot`, `/efi`, symlinks, unmounted paths, wrong filesystems and baseline drift are rejected. The candidate never chooses a disk. Payload is installed under `/usr/share/omarchy/pi4-cts`; scripts under `/usr/lib/omarchy/pi4-cts`; a PreTransaction check guards later package upgrades and a PostTransaction hook rechecks then publishes overlay before config, with file readback and sync. Existing DMA bytes/config lines remain unchanged.

For first-install read-only preflight, after a real firmware archive exists, the parent extracts it into a fresh root-owned temporary directory without installing it, then invokes its helper with that extracted payload. For example, with `/root/cts-preflight` already created empty and root-owned:

```bash
sudo bsdtar -xpf raspberrypi-4-pftf-cts-1-1-aarch64.pkg.tar.zst -C /root/cts-preflight
sudo /usr/bin/python -I /root/cts-preflight/usr/lib/omarchy/pi4-cts/media-sync.py check /root/cts-preflight/usr/share/omarchy/pi4-cts
```

This uses the actual package bytes and requires the configured UUID mount and exact baseline before the transaction. It writes no firmware. Parent must keep that card mounted and unchanged through the transaction.

ALPM hook limitations are explicit: a new package's pretransaction hook is unavailable on its first install, and a failed posttransaction hook does not revert the root package transaction. First installation therefore requires prior parent-reviewed media identity/baseline validation and physical recovery readiness; after the transaction, **any hook error is a stop/no-reboot state requiring rollback**, never success. Root rollback also does not undo card writes. The package is inactive pending review and real payload/transaction tests; normal public update support must adopt this ownership/configuration mechanism and test failure/removal/downgrade semantics before publishing. It cannot silently broaden a baseline to unknown cards.

Both halves are required: the driver without property strips unusable CRTSCTS, and the property without the driver supplies no CNTL hardware gating. A matching kernel/headers pair alone is not the complete deployed candidate.

## Build procedure after the parent's authorization

Use a single heavy-build owner; coordinate other projects, confirm Docker restart/RAM decision, sufficient host/VM memory and at least 40 GiB host/VM-volume free space before starting. No concurrent Zstd/GPU/kernel builds. This script does not restart or resize Docker. Preserve the prior `omarchy-pi-kernel-reviewed-work` volume; it supplies `/downloads` read-only. The new `omarchy-pi-cts-32-2-work` volume is disk backed and must be fresh. No shared source/cache writes, tmpfs builds, network, pulls, dependency installation, compiler substitution, skipped checksums or skipped signatures.

From the repo root, after authorization only:

```bash
cd build/upstream-pi/stable-4.5/cts-kernel-candidate
CTS_BUILD_AUTHORIZED=parent-approved CTS_MEMORY_MIB=3482 bash build-offline.sh
```

3482 MiB is the previous successful reviewed container limit, an example only: the parent must choose the actual approved value. The runner refuses unset/out-of-range memory, active containers, reused output and concurrent owners; pins image `sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2`, caps two CPUs/jobs with no extra swap and 512 PIDs, and writes the entire build log to disk. `SOURCE_DATE_EPOCH=1794113568` fixes the candidate build timestamp; ephemeral module signing keys still prevent a promise of byte-identical signed archives. All source signatures are verified with bundled keys offline. A missing cached tarball/signature/NVIDIA source/dependency is a real blocker; inspect the log, do not fetch/install or weaken verification. Cache completeness and image availability have not been queried with Docker in this lane.

`logs/input-guards.log`, `logs/image.json`, `logs/source-cache-volume.json`, `logs/docker-info.txt`, `logs/container-final.json`, `logs/run-hashes.txt`, `build-run.log`, `output/evidence/` and `output/SHA256SUMS` capture inputs, toolchain/build metadata, limits, exit/OOM state, cgroup peak/events/CPU and package hashes. Failed attempts remain available; do not rerun over them. The named container/volume remain for diagnosis. Parent must inspect exit status and all archive checks, including `drivers/check-candidate-payload.py`'s existing broad archive checks adapted to the new filenames, before marking build-qualified. No build manifest should be relabeled success from file presence alone.

## Candidate hold, deployment and recovery

Retain current IgnorePkg protection for kernel/headers and coordinated runtime/settings/support candidates. Add the new firmware package to the candidate hold if installed. Explicit local package transactions must contain matching kernel and headers and the companion firmware package; no partial `-Sy`, foreign module transplant or copied old headers. Hold release requires a capability-bearing normal kernel release, matching packages, durable firmware ownership/update tests, successful physical radio tests and demonstrated rollback. This private 32.2 version can sort below public 7.3-34: an unheld normal upgrade could undo the fix.

Before any transaction the parent must demonstrate the original recovery SD can boot and unlock encrypted root with physical help available. Retain hashes of cached 32.1 kernel/headers (and NVIDIA if installed), support/desktop 1-3, all relevant root snapshots and package state. Known 32.1 archive hashes: kernel `2164fb79c02442b9047166b07f1667558f1674c2ccf345d38b9f7e10e97ef8d8`, headers `1c90e860325eed52865869c060f762718784f9bda9cc9d7978fa636ce74f89e1`; they remain in `kernel-reviewed/packages/` locally. Verify again before transfer/use.

Create a fresh root snapshot and **separate** full SSD ESP and firmware-card archives with file manifests/hashes. Root Btrfs snapshots exclude FAT ESP, the firmware card and firmware variables. Existing saved archives/snapshots are evidence of availability, not demonstrated recovery. The companion's `/var/lib/omarchy/pi4-cts/config.txt.before` is only a file backup, not a substitute for those archives.

Before installing a replacement, preserve a uniquely named old UKI on the ESP, its Limine entry with the existing root/encryption command line, the old kernel modules tree and matching headers. Pacman normally removes versioned modules when replacing a kernel: retaining a UKI alone is insufficient. Parent should retain/copy the complete `/usr/lib/modules/7.3.0-32.1-omarchy` tree outside package cleanup and restore it at its original path after the transaction if needed for the previous entry; retain exact ownership/manifest evidence. Do not point the old entry at a newly regenerated UKI. Physically prove that entry boots/unlocks before considering it recovery. Keep the existing automatic SSD path and original SD recovery path unchanged.

Rollback from a running candidate before package removal, while its payload exists and the identified firmware card is mounted:

```bash
sudo /usr/bin/python -I /usr/lib/omarchy/pi4-cts/media-sync.py restore
```

This restores the pinned prior config and removes only the owned CTS overlay; it keeps the DMA overlay. Verify readback and the dedicated firmware manifest. Then in a single reviewed package transaction remove the exact-kernel-dependent companion and downgrade kernel/headers (NVIDIA too if installed) to the cached 32.1 pair. Pacman's exact dependency will block downgrading the kernel while leaving the companion installed; remove the companion first with its explicit restore already complete, then downgrade immediately with the holds retained. Use explicit local archives (`pacman -U` through the parent-approved transaction path); no dependency bypass. Regenerate the old initramfs/UKI through the existing Limine hooks and run support's boot verification. Verify release, byte correspondence, modules and old menu entry. Restore the separate ESP archive if required; a root snapshot restore alone cannot repair it.

If the candidate cannot boot, choose the proved old entry or original recovery SD, unlock/mount encrypted root, mount the **identified** ESP and firmware card separately, restore prior card config/remove CTS overlay from the saved manifest, downgrade the coherent package set in the recovered root and regenerate prior boot files. Do not overwrite EEPROM, RPI_EFI.fd, partition tables or unrelated firmware settings to undo this property. Restore full firmware/ESP archives only against their verified original devices and hashes when file-level recovery is insufficient. Parent must demonstrate the restored old kernel and DMA behavior physically before closing rollback.

After a candidate boot, parent must verify release/header identity, AUX binding, final property and unchanged pinmux/DMA/display/storage/taint, then actual powered CTS recovery, HCI initialization, repeated scans, pairing, usable peripheral traffic, reconnect, cold/warm boot and supported suspend/resume. Initialization timeout, stalled RX/TX, unexpected RTS/throttle behavior or any boot/storage/display regression triggers coherent rollback. Existing powered-window evidence and host tests justify this build candidate; they do not establish working radio or recovery.
