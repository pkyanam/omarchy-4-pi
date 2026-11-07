# Omarchy 4.5 on Raspberry Pi 4

This document records the design and validation boundary for the 4.5 port. For installation, use the [4.5 release notes](releases/v4.5.0.md) and [quick start](../README.md). Follow the [work ledger](../plans/omarchy-4.5-pi4.md) for implementation and test results. The immediate targets are Raspberry Pi 4 Model B with 4GB and 8GB RAM; Pi 5 remains a separate, unvalidated target.

## What changes in 4.5

Omarchy 4.5 adds floating workspaces with a dock, per-monitor workspaces, expanded language support, revised notifications, video backgrounds and theme intros, and improvements to shell dispatch and theme switching. It also broadens ARM support. These features have coupled dependencies: the compositor, titlebar plugin, Quickshell, Qt, shell source, and migration scripts must be updated together. See the [official announcement](https://omarchy.org/news/2026/11/omarchy-4-5/) and [released source](https://github.com/omacom/omarchy/tree/ac2690cd7be4f47e4a255f5e2e78d904d436b068).

The existing Pi fork already contains much of the Quattro architecture, including Lua Hyprland configuration and a single-process Quickshell desktop. The task is to integrate the released changes while preserving the port's boot, installation, and resource policies. An ARM64 ISO for another hardware family is not a Raspberry Pi image.

## Package and boot decisions

The fresh 4.5 image targets the stable 4.5 ARM64 compositor and application packages with their matching Arch Linux ARM library set. The November rolling ALARM graphics libraries differ from the release package dependencies. Selectively mixing those sets can produce an unresolvable package transaction or a plugin/runtime failure. Exact versions, repository observations, recipe identities, and source links are in the [upstream audit](../plans/omarchy-4.5-upstream-audit.md).

The fork must continue to build its own adapted `omarchy` and `omarchy-settings` packages. Official ARM64 application binaries can reduce source compilation, but official core packages must not overwrite the Pi adaptation. Package signatures remain required. Required runtime packages must be resolved explicitly; silently skipping them can leave a desktop feature missing or stop the migration queue later.

Keep the Pi firmware, U-Boot, `linux-aarch64`, and ext4 layout for this port. Generic ARM/PC initramfs fragments, Limine settings, and other vendors' firmware are not interchangeable with that boot chain. The [ALARM Pi 4 instructions](https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4) define the board-specific starting point. A vendor-kernel/media experiment must use a separate recoverable image and its own validation results.

Do not silently redirect an existing rolling installation to the new package set or downgrade selected libraries in isolation. Fresh images are the first validation target. An in-place transition is a separate release gate and needs a cloned installation, a complete reviewed transaction, and a working whole-card rollback.

If a direct fresh installation fails, rerun the same checkout as the same user with the original options plus `--resume` (for example, `./install-rpi4.sh --minimal --resume`). A root-owned checkpoint must match the source commit, checkout location, user, home and installation mode. Completed default seeding is skipped on retry; required package and system/user setup is retried. A changed checkout, completed installation, or legacy card cannot use this option to replay setup. Disposable image-factory failures can instead discard their private workspace and rebuild.

## Pi resource policy

Use the 4GB board as the baseline. Extra memory on the 8GB board permits a larger working set; it does not make the same CPU or GPU faster. Both targets start at stock clocks with thermal protection intact. Neither CPU overclocking nor arbitrary firmware GPU-memory/CMA allocations is a substitute for fixing runtime dependencies or measuring resource use.

Fresh-user defaults should start with a static background, opaque bar, reduced motion, and disabled theme intros. Floating workspaces and the dock remain part of the intended experience. Existing users' display, font, layout, and effect choices need preservation; a core update must not replay owner provisioning or overwrite their configuration.

Pi memory policy must be effective after all configuration files are merged. Upstream's later-named zram and sysctl files can otherwise override the port's intended half-RAM compressed swap and bounded writeback defaults. Workload scopes must sit under the monitored application slice, leaving the compositor's session outside the OOM candidate subtree.

Package staging belongs on disk, including the first installation and a failed-update retry. Build concurrency and compression limits must apply before the first package build. Preserve explicit user limits and lower concurrency when available memory is low. Container tests can verify budget selection and command arguments; live cgroup membership, enforcement, and desktop responsiveness need Linux runtime and board evidence.

## Graphics and media are separate gates

A loaded V3D module or render node establishes driver availability. It does not prove that Hyprland, Chromium, or a video player is using the intended hardware path. Verify the actual compositor renderer and check for software rendering, GPU resets, and modesetting errors.

Hardware video decoding requires a working kernel decoder interface, userspace support, and demonstrated playback using that decoder. Chromium's package configuration alone does not establish acceleration, and lack of VA-API does not establish failure of a V4L2 path. Record codec, resolution, frame rate, decoder identity, dropped frames, CPU use, and temperature for controlled clips. The [performance audit](../plans/omarchy-4.5-pi4-performance-audit.md) links the relevant Raspberry Pi, Linux, Mesa, and browser sources and defines the proposed measurements.

Do not infer display timing from scaling. Retain preferred-mode detection and the existing confirmed, reversible monitor overrides. Missing EDID, HDMI audio, and physical cable behavior need their own tests. The historical NEC observations are documented in [the earlier hardware follow-up](pi4-hardware-follow-up.md); they are not a 4.5 hardware result.

## Validation sequence

1. Run focused package, update, provisioning, boot-configuration, image-integrity, resource-policy, and shared desktop fixtures in native ARM64 Linux. Preserve complete logs and identify unavailable runtime coverage.
2. Assemble a candidate with exact source and recipe identities, a strict JSON manifest, complete required packages, and verified signatures. Audit the actual mounted filesystem and run the packaged ARM64 Hyprland configuration parser.
3. Verify that the factory contains no reusable account credentials, SSH host identity, or pacman private master identity. First boot must generate its own identity and complete root growth, hardware setup, and owner provisioning in the required order. Failures must remain visible and retryable.
4. Flash disposable media for the 4GB Pi first. Exercise Imager customization, offline/online setup, hostname and SSH choices, first login, second boot, desktop input, display modes, locking, capture, Wi-Fi, Bluetooth pairing, and audible playback.
5. Run the controlled idle, browser/editor, mixed-build, video, and thermal workloads at stock clocks. Record the exact board revision, power supply, cooling, storage, monitor/cable, image hash, and package versions. Inspect screenshots and short recordings separately from unrecorded performance measurements.
6. Repeat on the 8GB Pi and report it independently. A pass on one board does not qualify the other. Test upgrade/retry paths on cloned old installations before advertising in-place upgrades.

The quantitative workload protocol and proposed acceptance thresholds are in the [performance audit](../plans/omarchy-4.5-pi4-performance-audit.md). They are testing targets, not achieved benchmark results. No Raspberry Pi OS performance-parity or Pi 5 support claim follows from a passing source suite.

## Evidence to keep with a candidate

Keep the source commit, recipe commit, package versions and signatures, manifest, compressed-image checksum, mounted-root audit, build log, and test logs together. Identify whether each result is a fixture, assembled-image check, running desktop check, or physical-board observation. A successful Git merge, core receipt, or configuration parse does not establish a bootable, responsive desktop.

Physical results should include both passing behavior and unresolved failures. Keep credentials, private keys, raw preseed files, and NetworkManager secrets out of shared logs. Back up the entire test card and boot partition before kernel/package experiments; changing the Git checkout is not a rollback for an installed system.
