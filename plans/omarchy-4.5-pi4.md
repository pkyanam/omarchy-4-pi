# Omarchy 4.5 Raspberry Pi 4 upgrade

## Status

The Omarchy 4.5 Pi 4 candidate is built and verified locally. Its exact clean source is `3710ff523aece0229a1383597c00d6894bb30e13` on `codex/omarchy-4.5-pi4`; later documentation commits record this result. Baseline: `393f48c3` on this fork's `main`. Upstream: released `v4.5.0`, commit `ac2690cd7be4f47e4a255f5e2e78d904d436b068`. The adapted core/settings pair is `4.5.0.pi4.1-1`, using reviewed recipes at `c7a1ef7f86cccab072fb11f22564862c03f50199`. The legacy source `version` file remains upstream's `4.0.0.alpha`; installed version reporting uses package metadata. Physical Pi 4 boot and performance qualification remain outstanding, and no in-place rolling-to-stable upgrade or Pi 5 support is claimed.

Artifacts are in `build/image/`: `omarchy-4-pi-20261107-3710ff52-minimal-candidate.img.xz`, its `.sha256`, `.manifest.json`, `.audit.txt`, matching `.os-list.json` and `os-list.json`. The image is 2,844,278,596 bytes (2.649 GiB), expands to 12 GiB, and records 858 installed packages. Compressed SHA-256: `7bd9f6efc8a4157b5e542ab257842705d52e9de43760cbf427155e773f291bcb`. See [the local flashing and verification guide](../build/image/README.md). No media was flashed and no public release was published.

The immediate targets are Raspberry Pi 4 Model B with 4GB and 8GB RAM. Raspberry Pi 5 with at least 4GB RAM is a later target and must have its own boot, graphics, and hardware validation before support is advertised.

## Work ledger

- [x] Confirm the official Omarchy 4.5 release and inspect the existing port.
- [x] Confirm GPT-6.1-Sol, Max reasoning, and Fast/priority delegation support.
- [x] Research upstream changes, ARM64 package requirements, and the integration boundary.
- [x] Audit Pi 4 graphics, memory, storage, CPU, thermals, and desktop resource defaults.
- [x] Audit image construction, first boot, package rebuilding, migrations, and existing-install updates.
- [x] Establish the focused test baseline and resolve implementation priorities.
- [x] Integrate the released source and validate Pi-specific fixes with focused fixtures.
- [x] Build and audit an ARM64 image using the bounded native Linux builder.
- [ ] Validate the running desktop and representative workloads on physical Pi 4 hardware.
- [x] Record release gates, rollback procedures, and remaining Pi 5 work.

## Working rules

Preserve Pi firmware/U-Boot, Arch Linux ARM repositories, first-boot owner provisioning, update guards, and stock clocks. Measure performance before claiming gains. Distinguish fixture tests, assembled-image checks, running-desktop checks, and physical hardware results. Keep changes reviewable and avoid publishing an unvalidated release.

## Integration decisions

Use the exact released source tag and a coherent stable ARM64 compositor/library package set for the first fresh image. Evaluate Omarchy's signed ARM64 application binaries to replace expensive local application builds, while retaining the locally adapted Pi core/settings pair and Pi boot packages. Mixing release Hyprland/titlebars with newer rolling ALARM libraries is not an acceptable shortcut. Existing rolling installations must not be silently redirected or partially downgraded; their transition needs an explicit tested boundary.

The upstream merge has 13 textual conflicts. Preserve Pi semantics when resolving them; seven further jointly changed paths and new upstream platform/package policy also need semantic review. The original `main` remains the baseline while this integration branch is developed.

Audit reports: [upstream and packages](omarchy-4.5-upstream-audit.md), [Pi performance](omarchy-4.5-pi4-performance-audit.md), and [installation and updates](omarchy-4.5-pi4-install-audit.md). These reports describe baseline findings; implementation progress and validation belong in this ledger.

## Evidence

- [Official Omarchy 4.5 announcement](https://omarchy.org/news/2026/11/omarchy-4-5/)
- [Upstream v4.5.0 release](https://github.com/omacom/omarchy/releases/tag/v4.5.0)
- [Existing Pi performance research](../docs/pi-performance.md)
- [Existing Pi upgrade procedure](../docs/pi-upgrade.md)
- [Earlier physical Pi 4 observations](../docs/pi4-hardware-follow-up.md)
- [4.5 design and validation guide](../docs/omarchy-4.5-pi4.md)

## Validation results so far

- Baseline audit: 19 Mac fixture suites passed unchanged; screensaver passed after an isolated host-output adapter. Root-required optimization coverage and firmware extraction needed Linux.
- Native ARM64 test image prepared from Node 24 / Debian Bookworm, with Bash 5, Python, jq, Lua, FFmpeg, system utilities, and compiler tools. Tests use isolated containers, a read-only checkout, no network, and bounded CPU/memory.
- Seven focused recording/menu suites completed successfully. The first audio-only run exposed a missing checkout `bin/` on the harness PATH; correcting that environment made the targeted rerun pass. Recording coverage includes the Pi 30fps fallback, concurrent start/stop handling, process ownership, mixed-audio failure handling, and real FFmpeg 48kHz output. Logs: `build/validation/capture-menu-tests.log` and `build/validation/screenrecording-wf-audio-tests.log`.
- These are automated fixture/media checks. No image assembly, first boot, graphical desktop, or physical Pi result is recorded yet.

Integration review: all four production assignments are complete and textual merge conflicts are resolved. Native ARM64 Linux now passes the new package resolver/build/update, verified offline Node preload, real packaged mise lazy-shim migration, Pi performance (including Lua), image manifest/workspace/release, and unprivileged first-boot keyring fixtures. The root-owned rootfs fixture also passes with actual ownership checks and injected boot, manifest, architecture, identity, firmware and zram faults. Complete outputs are under `build/validation/linux/`; unavailable namespace/cryptsetup checks are explicitly marked in their logs. Legacy test reconciliation and remaining shared-suite checks continue before the integration commit and actual image assembly.

Final source checks: the reconciled broad Pi, update-safety and upgrade-guide suites passed in native ARM64 Linux, including the new inherited-policy regression. The unprivileged LUKS journal fixture passed its simulated crash/retry cases; real cryptsetup cases remain unavailable. The CLI suite and platform/pacman template suites passed after adding the target's GNU awk and a real pacman-conf to the Debian test environment. Logs: `build/validation/shared-final-tests.log` and `build/validation/final-followup-tests.log`. The current environment is Node 24 / Debian Trixie with modern Python and the signed target mise binary; the earlier Bookworm checks are historical.

Owner retry review moved authorized-key writes to the owner's privileges and added symlink, hardlink, redirected-home and existing-key-preservation checks. `build/validation/linux/rpi45-provisioning.log` is the passing final result. The fixture now changes modes only on its own stubs, so it also runs against a read-only source mount. Warning-level ShellCheck passed. The checkout's five whole-merge whitespace warnings are unchanged upstream lines; the Pi changes pass the scoped whitespace check.

Native image builds verified the signed ALARM root filesystem and exposed a container partition-device readiness failure, then a transferred Git ownership issue. Those were fixed in `d6b3eef9` and `251e5018`. The third build completed dependency-checked signed desktop installation and local Pi package construction, then the real ARM64 Hyprland parser rejected upstream cursor startup code without a live session. `54deda78` fixes that path; the cursor fixture and native installed parser pass. Logs: `build/validation/candidate-image-build{,-2,-3}.log` and `build/validation/native-hyprland-parser.log`. The failed images are diagnostic only; no patched failed image is a deliverable.

The [independent final source review](omarchy-4.5-final-review.md) found OEM environment/Node prerequisites, future runtime reverse-dependency constraints, interrupted-install retry refusal, and container-only Mac catalog URLs. All are corrected through `6bd47bdb`. A real libalpm transition fixture passes; root-owned installer retry/refusal tests pass; Mac catalog relocation preserves integrity and rejects corrupted copies. Related package, build-policy, resource and image-release suites pass again in native ARM64 Linux. Warning-level ShellCheck and the Pi whitespace check pass. Final image assembly and physical tests remain distinct gates.

The fourth native build passed its actual Hyprland parser and 190 of 191 mounted-image checks. The remaining check incorrectly demanded a package literally named `chromium`; the resolved, signed `omarchy-chromium-bin` package supplies Chromium. The audit now reads installed `Provides` metadata and separately requires the browser launcher. Its root-owned fixture passes and rejects a missing provider declaration or launcher (`build/validation/linux/rootfs-provider-audit.log`). A fresh build will include the correction.

Native runtime checks on that otherwise complete fourth image passed in a disposable overlay over the read-only raw image, with networking disabled: Hyprland, Quickshell and titlebar-library dependencies resolve; Quickshell runs; the packaged systemd unit definitions verify; a new Pi user's fontconfig resolves Paper Mono; verified Node `v26.13.0` and npm `11.20.0` execute through the actual mise shims without a user mise config or a global offline-mode override; and two fresh pacman keyrings populate from packaged public trust with distinct private-master identities. The offline reshim step warns about uninstalled lazy agent tools, which are intentionally not downloaded in this check. Evidence: `build/validation/native-runtime-preflight.log`; procedure: `build/validation/audit-native-runtime.sh`. These checks do not boot systemd, load the titlebar plugin into a running compositor, render a desktop, or exercise physical Pi hardware.

Final build: `build/validation/candidate-image-build-5.log` records successful native signed package installation, local core construction, the actual Hyprland parser, all 192 mounted-image invariants, clean ext4 and FAT checks, compression, catalog generation, host copy, and original-hash/host-URL validation. The final image also passed the disposable-overlay runtime checks above, adding actual Chromium `148.0.7778.96` startup (`build/validation/native-runtime-final.log`). The copied manifest is strict JSON with clean candidate provenance and the complete final package inventory; its source commit and hashes match the delivered artifacts. Raspberry Pi Imager 2.0.12 is installed on the Mac and meets the launcher's minimum version. The remaining gate requires Preetham's 4GB and 8GB boards: first boot and retry ordering, desktop rendering/input/audio/network, actual hardware acceleration, and controlled resource/thermal workloads. No physical validation result is inferred from these local checks.

## Validation access

Preetham has one 4GB Pi 4 and one 8GB Pi 4, neither currently running Omarchy. Proceed with fresh-image preparation; no previous installed system is required. No Pi 5 is available. OrbStack has been started on the Apple-silicon development host and supplies native ARM64 Linux with an initial 1 CPU / 2GiB budget and no running containers. Build/test concurrency must remain bounded. Desktop and board behavior cannot be established by container checks alone.
