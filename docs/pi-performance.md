# Pi 4 efficiency: research, implementation, and measurement

Research date: September 4, 2026. Target: **Raspberry Pi 4 Model B, 4GB+ RAM**, with 8GB recommended for larger development workloads. Objective: at least Raspberry Pi OS parity on a declared workload suite while retaining Omarchy's desktop and agent workflows. **Parity is not yet measured or achieved.** Changes described as implemented below are in source, not the original `v0.1.0-rc.1` image.

Follow-up implementation: [the next alpha's CPU, memory, build, logging, and opt-in clock controls](pi-tuning.md). The initial memory finding below has been corrected after inspecting what the upstream ARM package actually installs, not just what exists in this source tree.

## Hardware and kernel findings

Follow-up: [verified extraction and comparison of official Raspberry Pi OS firmware/kernel packages](rpios-driver-audit.md) includes byte-level comparisons against the published image and a vendor-kernel candidate boundary.

The Pi 4 combines four Cortex-A72 cores, shared system memory, VideoCore VI graphics, USB 3, Gigabit Ethernet, and micro-HDMI. CPU throughput, GPU bandwidth, storage latency, and cooling all matter; tuning only an idle-memory number is insufficient. Raspberry Pi specifies a 5V/3A power arrangement for this board. Good cooling and power are prerequisites for repeatable sustained tests, not optional benchmark accessories. [Raspberry Pi hardware documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html).

This image uses Arch Linux ARM's AArch64 distribution, mainline-style `linux-aarch64` kernel and U-Boot route, not Raspberry Pi OS's complete vendor integration. A Raspberry Pi OS recipe, firmware utility, kernel overlay, or acceleration flag cannot be assumed to transfer unchanged. This explains why a missing legacy `vcgencmd` device is not by itself a health failure. Kernel/firmware changes should be separate, boot-tested releases with recoverable storage. [Arch Linux ARM's Pi 4 platform notes](https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4), [Raspberry Pi kernel documentation](https://www.raspberrypi.com/documentation/computers/linux_kernel.html).

Mesa's V3D driver handles rendering and V3DV handles Vulkan; VC4 handles display on Pi 4. Our source already enables full KMS, includes Mesa/Broadcom Vulkan, and applies an Aquamarine modifier compatibility workaround. Preserve the working graphics path first. An isolated A/B test of that workaround is a future investigation, not grounds to remove it from every board. Hardware rendering readiness does not establish accelerated browser video decoding. [Mesa V3D driver documentation](https://docs.mesa3d.org/drivers/v3d.html).

Increasing `gpu_mem` does not give Pi 4 more 3D performance: its 3D allocations are managed dynamically by Linux. Excess firmware-reserved memory takes RAM away from applications, while the minimum reservation disables some firmware features. We therefore do not add a blanket `gpu_mem=16`, oversized allocation, or arbitrary CMA value. Missing EDID is treated as a display-detection problem, not solved through memory tuning. [Raspberry Pi legacy memory options](https://www.raspberrypi.com/documentation/computers/legacy_config_txt.html#gpu_mem).

CPU governors are policy, not magic speed switches. The initial audit changed none; the follow-up alpha adds a boot-time dynamic-governor default after the inspected ALARM config showed `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y`. It chooses only supported governors and leaves later user profile choices alone. Stock clock and thermal limits remain unchanged. [Linux CPU performance scaling](https://www.kernel.org/doc/html/latest/admin-guide/pm/cpufreq.html).

## Source audit and implemented efficiency work

| Area | Finding | Decision/change |
| --- | --- | --- |
| Package staging | The builder copied the complete checkout before removing artifacts and Git history. A developer checkout can contain multi-gigabyte images. | Stream source with build directories and Git metadata excluded before copying; keep working edits. This removes unnecessary disk traffic and staging-space consumption, without claiming a measured wall-clock gain. |
| Update retry | Advancing Git HEAD was treated as evidence that installation had succeeded. | Record the installed source commit only after successful package installation. Retry failed builds even when HEAD is current. |
| Screensaver | An optional renderer was required by a default feature, causing a tight error loop. | Earlier fix makes `ttfx` required and audit-gated; the runtime exits on failure. Updates now reconcile required minimal runtime packages too. |
| Compositor | Default blur and shadows are already disabled; workspace animation is already off. | Keep those efficiencies. Do not claim savings from disabling something already disabled, or strip the desktop blindly. |
| Agent/build contention | Unbounded builds can compete with the compositor and browser. | Add opt-in `omarchy pi run`: user-scope resource limits and RAM-aware build parallelism; no always-running service. |
| Shell wakeups | Agent data refresh defaults to 900 seconds; the panel's 30-second text timer runs only while open. Local plugin changes use inotify. | Preserve event-driven behavior and existing lazy UI updates. Do not add a Pi-specific sub-second monitoring loop. |
| Diagnostics | Aggregate free memory cannot distinguish CPU contention from reclaim or SD-card stalls. | Add `omarchy pi report [--json]`: native sensors, CPU policy, zram statistics, and PSI. Unknown sensors remain unknown. |
| Memory | Correction: zstd/whole-RAM defaults exist in source, but the ARM package recipe omits them and the inspected ALARM kernel does not enable the zstd zram backend. | The alpha explicitly installs half-RAM logical zram using the kernel-default compressor and app-scope oomd policy; audit the packaged result. |

Zram trades CPU work for reduced storage-backed paging; logical device size is not RAM preallocation, and compression ratio depends on data. LZ4 versus zstd and different sizes belong in controlled tests with actual builds/browser tabs, not folklore defaults. [Linux zram documentation](https://docs.kernel.org/admin-guide/blockdev/zram.html).

PSI measures time stalled on CPU, memory, and I/O; these counters are a better diagnostic companion to utilization than a free-RAM screenshot alone. The report samples existing files once. It does not poll forever, collect process command lines, read agent credentials, or enumerate serial numbers, hostnames, or network addresses. [Linux PSI documentation](https://docs.kernel.org/accounting/psi.html).

## Update path audit

Upstream Omarchy uses its own pacman packages/channels plus system packages, migrations, AUR, and mise updates. The Pi port cannot inherit the x86 package-channel behavior wholesale. [Omarchy update manual](https://omarchy.org/manual/updates/).

The port's main update route now checks the following before update mutations:

1. Native `aarch64`; a readable Pi profile and source checkout.
2. Origin is the project's canonical GitHub repository, `pkyanam/omarchy-4-pi`; branch is `main`, tracking `origin/main`; no dirty source tree.
3. Pacman's resolved architecture is `aarch64`; only `core`, `extra`, `alarm`, and `aur` repositories are enabled; no upstream Omarchy/x86 mirror is configured.
4. Fetch the explicit Pi main ref and use fast-forward-only integration. No automatic upstream repository replacement, checkout reset, or local-edit overwrite.
5. Install missing required ARM runtime packages using the package-only installer leaves, rebuild the local core, then write a successful-install marker. No replay of owner provisioning or user config reset.
6. Use `archlinuxarm-keyring`, never the x86 `archlinux-keyring` step. Exclude locally rebuilt core packages from AUR namesake replacement.

Direct system package updates and package-config refreshes also check the package configuration. The legacy x86 Quattro upgrader now refuses ARM before installation. The release link in the confirmation prompt points to this project. Existing Pi channel-switch restrictions remain.

This is protection against accidental upstream mixing, not a security sandbox against a user who deliberately rewrites root configuration, Git hooks, or trusted scripts. Custom repositories and development branches now require deliberate review rather than silently participating in the standard update path. Package signatures remain enabled. Arch Linux ARM rolling packages may still encounter upstream ABI or hardware regressions: refusing x86 sources does not guarantee every future ARM update works.

The root-owned success receipt is `/var/lib/omarchy/rpi4-source-commit`. A missing receipt triggers one core rebuild to establish it. A failed package install never advances it. The notification command also recognizes a pending rebuild.

Rollout caveat: the original release's installed updater predates this guard. Reading the new README does not retrofit old code. A freshly built image includes these safeguards from its first update; an existing installation needs a reviewed bootstrap/update to the new core. No image has been rebuilt or flashed as part of this source audit. The source branch remains a rolling integration branch, not an atomic, fully tested binary-update channel.

## Agent-friendly work without making the Pi do everything

Omarchy already provides lazy-loaded agent launchers, default-agent selection, a usage panel, terminal workflows, and customization guidance. Retain those rather than adding an independent assistant daemon. CLI compatibility and provider authentication still need verification per ARM tool. Prefer hosted inference or a remote compute host for large models; use the Pi as the responsive workspace, editor, terminal, and orchestration endpoint. [Omarchy AI manual](https://omarchy.org/manual/ai/), [Omarchy terminal manual](https://omarchy.org/manual/terminal/).

The new workload scope keeps the calling terminal and working directory. On a four-core machine it requests a 300% CPU quota, lower relative CPU/I/O weights, a 50% physical-memory reclaim threshold, and a 65% hard memory ceiling. Build parallelism is the smaller of available CPUs minus one and whole GiB of available RAM, with a floor of one job. This is a conservative starting policy, not a proven optimum. A memory-limit breach may kill that workload; it is not a guarantee against system-wide OOM. Separate invocations have separate budgets, so start one heavy job at a time. [systemd resource-control reference](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.resource-control.xml).

`--plan` makes no system change. Actual execution requires the systemd user manager and working cgroup controllers; creation failure is returned rather than silently launching unrestricted. `--expand-environment=no` prevents systemd from changing literal dollar signs in prompts. No new sudo grants or agent auto-approval flags are added. This limits resources, not file/network privileges; agents retain the invoking user's access. [systemd-run reference](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd-run.xml).

See [Pi workflows](../manual/pi.md) for commands and safe agent handoffs. Future QoL candidates: opt-in pressure notifications with hysteresis, an update provenance card, and remote-build presets. None should add constant animation/polling or enable SSH, tunneling, or remote services without consent.

## Raspberry Pi OS parity protocol

Use the same physical Pi, RAM size, power supply, cooler, display mode (1920×1080 or the test monitor's 1920×1200 at 60Hz/1×), storage model, network, and ambient temperature. Compare current supported 64-bit Raspberry Pi OS Desktop against a named Omarchy image. Record exact OS/kernel/Mesa/browser/compiler versions, firmware, governor, and clocks. Do not compare an overclocked Omarchy run against stock Raspberry Pi OS or use a different SSD for one side.

| Workload | Measurements | Acceptance target |
| --- | --- | --- |
| Idle desktop, 10 minutes after settling | CPU time, available RAM, PSI, temperature, wall power if a meter is available | No unexplained background load; no worse sustained power/pressure beyond run-to-run noise |
| Terminal/editor and workspace switching under a fixed background build | Input-to-display latency with repeatable capture; p95 frame time | No worse responsiveness; throughput tradeoff reported separately |
| Browser with fixed pages and local video clips | Load times, CPU/RAM, dropped frames, decoded codec and actual acceleration | No regressions; explicitly report a video-decoding gap rather than calling it parity |
| Fixed source build, dependencies pre-cached | Wall time, CPU time, peak RSS, storage writes, PSI | Same or better throughput at matched job counts; compare budgeted mode separately |
| 30-minute mixed load, then idle recovery | Temperature, actual frequency, voltage alarms, errors, time to recover | No crashes/corruption or active undervoltage; no sustained thermal throttling |
| Reboot, lock/wake, updates | Boot-to-usable time and functional checks | Reliability is mandatory, not traded for speed |

Run at least five repetitions where practical, separate cold/warm cache results, report medians and spread, and keep raw logs. A benchmark score alone is not sufficient to claim the desktop is equally usable. Use `omarchy pi report --json` before/after and `vmstat 1 61` during a sample; on Raspberry Pi OS collect equivalent `/proc` and `/sys` counters. No stress tests or storage-write benchmarks are run automatically by these helpers.

Current evidence: automated fixture tests exercise update refusal/retry, scope construction/failure, native sensor parsing, and source-staging exclusions. No new physical-Pi speed, power, cgroup-enforcement, or Raspberry Pi OS comparison measurements were made in this pass. The previous user's successful desktop report does not fill those blanks.

## Original overclock design — now implemented for alpha

The proposal below informed the implementation. The [current operational guide](pi-tuning.md) is authoritative: supported actions are status/preview/apply/confirm/restore, no clock is enabled by default, and physical-board validation remains outstanding.

A future `omarchy pi tune` could provide **inspect**, **preview**, **apply**, and **restore**, with stock as the default. Clock experimentation is separate from baseline efficiency work. There is no universally safe frequency for every board, and thermal protection cannot prevent every instability or storage corruption caused by an unstable clock.

The proposed workflow requires explicit consent, a backup, exact board/kernel/firmware identification, a healthy power baseline, sufficient cooling, and a physical boot-config recovery path. It would save the original config and show an exact diff before changing an individually selected clock. It would never set `force_turbo=1`, disable thermal protection, increase the thermal limit, or silently set voltage/SDRAM/GPU-wide knobs. Current firmware documents automatic voltage scaling for overclocking; manual voltage overrides change that behavior, so they are not a beginner preset. [Raspberry Pi clock and voltage documentation](https://www.raspberrypi.com/documentation/computers/config_txt.html#overclocking-options).

After reboot, actual frequency and sustained performance must be measured, not inferred from a config line. A short stress pass is insufficient: check longer mixed CPU/GPU/memory/storage workloads, cooldown, and reboot reliability. An unconfirmed profile should revert when the system can boot, but an unbootable or corrupted system may require manual restoration; no software-only rollback promise can cover that. Thermal throttling begins as temperature approaches the documented 80–85°C range, so the design should warn well before it rather than aim to operate at the limit. [Raspberry Pi thermal management](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#frequency-management-and-thermal-control).
