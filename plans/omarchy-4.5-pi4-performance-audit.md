# Omarchy 4.5: Pi 4 performance architecture audit

Audit date: November 6, 2026. Source baseline: `393f48c3cd6e32e36111064fa99d2f59e4449aa5`. Upgrade target: upstream `v4.5.0`, peeled commit `ac2690cd7be4f47e4a255f5e2e78d904d436b068`. Immediate hardware scope: Raspberry Pi 4 Model B, separately tested in 4GB and 8GB configurations. Pi 5 with at least 4GB is deferred.

This is a report-only audit. This research task changed only this report: it changed no implementation files, installed no packages or host tools, started no builds or hardware workloads, and committed or published nothing. Physical Pi availability and SSH access remain pending. All performance targets below are proposed release gates, not benchmark results. The parent integration task shares this checkout and may change other files concurrently; local source links below refer to the audited [baseline tree](https://github.com/pkyanam/omarchy-4-pi/tree/393f48c3cd6e32e36111064fa99d2f59e4449aa5), not a claim that the final working tree is unchanged.

## Recommendation

Keep the existing ALARM firmware/U-Boot/kernel path and the substantial Pi safeguards already present. Integrate the released 4.5 shell, including its bounded wallpaper decoding, while explicitly retaining Pi memory and boot policy. Fix scope placement, build staging and bootstrap budgeting, and conditional boot-file handling before measuring the candidate. Start both Pi 4 memory variants with a static wallpaper, opaque bar, existing disabled blur/shadows, and disabled intros. Use 4.5's coherent reduced-motion toggle as a conservative fresh-install preset, then measure whether normal window animations can be offered without exceeding the interaction budget. Preserve existing users' choices.

The most consequential unresolved performance issue is the complete media path: a V3D renderer does not establish hardware video decoding. Current ALARM Chromium does enable V4L2, so a claim that its browser is compiled without that support would be wrong. Kernel decoder exposure, userspace decoder compatibility, and successful real playback still need to be established. A vendor-kernel experiment is a separate boot-tested image variant, not a prerequisite to merging the 4.5 desktop.

## Evidence and limits

| Evidence class | What was established | What it does not establish |
| --- | --- | --- |
| Local source, baseline `393f48c3` | Read the Pi documentation, every `bin/omarchy-pi-*` helper, `default/pi/`, Pi hardware setup, user/first-run setup, package/image builders, relevant shell code and audits. | Installed package contents, effective settings after boot, or physical performance. |
| Released upstream source | The existing fetched tag resolves to `ac2690c`; inspected its background, reduced-motion, intro, dock, startup, runtime-profile and memory files through `git show`. No duplicate repository fetch was performed. | Compatibility of every current ARM package with that source. |
| Primary upstream research | Official Raspberry Pi, ALARM packaging, Mesa, Linux, systemd, Hyprland/Aquamarine, Quickshell, Qt, Chromium and OWE sources were consulted. Exact source snapshots are linked below where significant. | That today's rolling package recipe matches an older image, or that upstream defaults are optimal on Pi 4. |
| Prior project evidence | [Driver extraction audit](../docs/rpios-driver-audit.md) and [hardware follow-up](../docs/pi4-hardware-follow-up.md) record earlier payload comparisons and alpha.7 observations. | New hardware verification in this audit. Earlier successful login, a 43.8°C snapshot, and zero voltage alarm do not demonstrate media acceleration, stable HDMI, or workload parity. |
| Host checks in this audit | Fourteen relevant shell files passed `bash -n`; the two Pi Python implementations passed in-memory compilation. Image headers and straightforward buffer arithmetic were inspected. The actual status helper was sourced with a failing renderer function and reproduced F6 without writes. | Shell fixture-suite success, active cgroup enforcement, visual correctness, boot success or speed. |

The source version is `4.0.0.alpha`; the README's latest alpha4 was described as built with 4.0.4. These labels must not be substituted for an installed manifest and image checksum. The [release](https://github.com/omacom/omarchy/releases/tag/v4.5.0) and [official announcement](https://omarchy.org/news/2026/11/omarchy-4-5/) establish the released upgrade target. Their desktop speed claims are upstream observations, not measurements on this port.

Read for this task: `AGENTS.md`, `agents/skills/install-scripts.md`, `shell-dev.md`, `command-metadata.md`, `visual-verification.md`, `acceptance-tests.md`, `migrations.md`, `docs/testing.md`, and the repository's privilege-escalation guidance. The project acceptance harness belongs in a disposable VM; its VM result must be supplemented by physical Pi testing. This audit does not modify a running desktop and therefore supplies no new screenshots or recordings.

## Existing architecture worth preserving

| Layer | Actual source behavior | Decision |
| --- | --- | --- |
| Boot and graphics | [Pi hardware setup](../install/hardware/raspberry-pi.sh) enables full `vc4-kms-v3d`, `max_framebuffers=2`, `disable_fw_kms_setup=1`, onboard audio, and module loading for `vc4`, `v3d`, `raspberrypi_hwmon`; installs `vulkan-broadcom`. | Preserve the working firmware/U-Boot integration; repair its conditional parsing rather than replace the stack casually. |
| Compositor | [Pi Lua](../default/hypr/raspberry-pi.lua) applies `AQ_NO_MODIFIERS=1` only when the hardware helper matches. [Look and feel](../default/hypr/looknfeel.lua) already disables blur, shadows and workspace animation; window/layer animations remain enabled. | Do not claim gains from disabling effects that are already off. Retain the modifier workaround until an isolated A/B test supports removing it. |
| Display | [Monitor defaults](../config/hypr/monitors.lua) use preferred mode and automatic output scaling, independently setting `GDK_SCALE=2`. [Display helper](../bin/omarchy-pi-display) has a timed, confirmed NEC EA243WM override and backed-up reset. | Scaling is not resolution. A Pi-friendly tested display profile is needed; do not globally force the NEC timing. |
| CPU | [Boot policy](../bin/omarchy-pi-cpu-policy) changes only an initial `performance` governor to supported `schedutil` or `ondemand`; its service precedes power-profiles-daemon. | Keep stock clock/voltage limits and the user's ability to disable the service. Verify the effective governor again after graphical login. |
| Compressed swap | [Pi zram configuration](../default/pi/zram.conf) requests half of Linux-visible RAM as logical zram, kernel-default compressor, priority 100. | Preserve this explicit ARM configuration; logical capacity is not additional physical memory. |
| OOM handling | [Apply leaf](../bin/omarchy-apply-pi-performance) installs an `app.slice` policy and 50% pressure/20-second oomd thresholds. System setup enables oomd. | Keep the compositor outside the candidate subtree; verify actual process placement and controllers. |
| Workload isolation | [Pi run](../bin/omarchy-pi-run) requests a transient user scope, 300% CPU quota on four cores, CPU/I/O weights 50, nice 5, `MemoryHigh=50%`, `MemoryMax=65%`, RAM-aware compiler hints, and literal argument preservation. Scope creation failure is returned. | Useful opt-in protection already exists. Correct its slice placement and do not describe it as a dedicated reserved core or a security sandbox. |
| Local package work | [Build budget](../default/pi/build-budget.sh) caps the default 4GB job count at two, or one below 2GiB available; typical 8GB ceiling is three jobs. Make/Cargo/CMake hints preserve pre-existing values; zstd packaging uses level 3 and bounded threads. | Preserve; apply before the very first build and audit recipes that invoke Ninja or explicit job flags. |
| Storage and logs | Pi dirty thresholds are 32MiB background/128MiB foreground; journals have 128MiB persistent, 32MiB runtime, seven-day limits and 512MiB keep-free. Image root is ext4 with `noatime`; expansion precedes owner setup. | Preserve pending measurement. Keep persistent diagnostics and filesystem durability. |
| Image production | The factory stages chroot temporary/cache data outside the 12GiB image, filters large source artifacts, removes build-only payloads, verifies offline filesystems, and records provenance. | These are real existing efficiencies. General/native entry points still need disk/memory limits. |
| Startup and agents | Docker is socket-activated. Agent tools largely use lazy launchers. Agent usage refresh defaults to 900 seconds; the panel's 30-second display timer is conditional. Plugin changes use inotify. | Preserve functionality and lazy/event-driven behavior; measure new collectors and optional panels rather than removing the desktop wholesale. |
| Updates | Source/ARM/repository guards, FF-only updates, required runtime reconciliation, successful-install receipt and retry behavior exist. Config reset and owner provisioning are not replayed by the Pi core updater. | Performance fixes must reach both fresh installs and upgrades without resetting personal settings. |

## Graphics, kernel and media research

### Rendering and display are different subsystems

On Pi 4, Mesa's V3D/V3DV implement graphics rendering while VC4 handles display; the kernel drivers cooperate through buffer management. Pi 4 uses V3D 4.2, whereas Pi 5 uses V3D 7.1. Preserve the distinction when interpreting `/dev/dri`: a render node and a loaded module do not prove the selected renderer or successful scanout. [Mesa V3D documentation](https://docs.mesa3d.org/drivers/v3d.html).

V3D has an MMU and uses shmem-backed objects; its rendering allocations are not a fixed `gpu_mem` carve-out. Display/decoder contiguous-memory requirements still need separate observation. Inspect `CmaTotal`, `CmaFree`, driver errors and actual allocation failures before altering CMA. Increasing firmware GPU memory is not a justified desktop optimization; do not apply a blanket `gpu_mem=16`, oversized `gpu_mem`, or arbitrary `cma=`. [Linux V3D buffer management](https://www.kernel.org/doc/html/latest/gpu/v3d.html), [Raspberry Pi legacy memory documentation](https://www.raspberrypi.com/documentation/computers/legacy_config_txt.html#gpu_mem).

`AQ_NO_MODIFIERS` disables DRM buffer modifiers. Current Aquamarine documentation establishes that behavior; it does not establish that the flag is a universal Pi speed optimization. Modifier removal can change buffer sharing and scanout behavior, so the correct experiment is compatibility and performance with exactly one setting changed. Do not also disable atomic modesetting, force software cursors or force software rendering. The existing Lua use of `hl.env()` is valid before display initialization. [Aquamarine environment reference at `42c3960`](https://github.com/hyprwm/aquamarine/blob/42c396067a5a59491a45138528d49238dd6e394e/docs/env.md), [Hyprland environment documentation](https://wiki.hypr.land/configuring/core/environment-variables/).

The earlier NEC report records zero EDID bytes and fallback modes with missing monitor identity. That is a display discovery problem until proved otherwise. Check the direct cable, connector, powered monitor, EDID validity and ELD/audio before attributing low resolution to RAM or graphics scaling. Confirm HDMI physically; a running compositor and clean `configerrors` are insufficient. Preferred/automatic output behavior and a GTK scale of two are independent controls. [Prior physical evidence](../docs/pi4-hardware-follow-up.md), [Hyprland monitor fields](https://wiki.hypr.land/configuring/core/monitors/).

### Keep the current and vendor kernel experiments separate

ALARM documents its AArch64 Pi installation as a mainline-kernel/U-Boot route. Raspberry Pi OS integrates its own kernel and firmware, with a different installation/update flow. Do not install `.deb` payloads or copy foreign `.ko` files into the current image. A candidate vendor image needs matched kernel, modules, DTBs/overlays, firmware, initramfs, package ownership and boot/update selection. [ALARM Pi 4 installation](https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4), [Raspberry Pi kernel guidance](https://www.raspberrypi.com/documentation/computers/linux_kernel.html).

The prior extraction audit found a published `7.2.2-2-aarch64-ARCH` image without the vendor `bcm2835-codec` module, while its inspected Pi OS donor was `6.18.39+rpt-rpi-v8`. Those are historical artifacts, not today's installed versions. Current ALARM source snapshot `748532c` names `linux-aarch64` 7.3.1-2. The Raspberry Pi source snapshot `31a3488`, branch `rpi-6.18.y`, has Makefile version 6.18.60 and Pi 4 defconfig enabling VCIO and the vendor codec. Source configuration is evidence of an integration difference, not proof of the packaged Pi OS kernel or working acceleration. [Historical payload audit](../docs/rpios-driver-audit.md), [ALARM recipe](https://github.com/archlinuxarm/PKGBUILDs/blob/748532cd1f8eea2d8f7a849d4f39ba5b74da60e1/core/linux-aarch64/PKGBUILD), [vendor defconfig](https://github.com/raspberrypi/linux/blob/31a34885388835dce2460744d7961f2b9e7dc416/arch/arm64/configs/bcm2711_defconfig).

### Browser and wallpaper decode require their own evidence

Pi 4 hardware supports H.264 decode through 1080p60 and H.265 decode through 4K60. This is a hardware capability ceiling, not a promise for Chromium, FFmpeg, OWE or screen recording on this distribution. VP9/AV1 playback must be reported separately; it cannot be inferred from the H.264/H.265 specifications. [Official Pi 4 specifications](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/).

Current ALARM Chromium source at `748532c` names Chromium `156.0.8078.79-1` and explicitly sets `use_vaapi=false`, `use_v4l2_codec=true`. Raspberry Pi's Chromium packaging likewise selects V4L2 on ARM64. Therefore, absence of VA-API support or a failing `vainfo` is not by itself a Pi V4L2 failure. Conversely, neither recipe proves that the installed browser uses a hardware decoder. The port's Chromium flags select native Wayland and extensions, not decoder verification. [ALARM Chromium recipe](https://github.com/archlinuxarm/PKGBUILDs/blob/748532cd1f8eea2d8f7a849d4f39ba5b74da60e1/extra/chromium/PKGBUILD), [Raspberry Pi Chromium rules](https://github.com/RPi-Distro/chromium/blob/2ba620333c7c01eb084f39e60e7289e83f6a959a/debian/rules), [current flags](../config/chromium-flags.conf).

Use a four-step proof for each codec/profile/resolution:

1. Identify actual kernel media devices and drivers through `/sys/class/video4linux`, `media-ctl`/`v4l2-ctl` where installed, and their enumerated formats. A webcam's `/dev/video0` is not codec proof.
2. Identify installed Chromium/FFmpeg/mpv versions, build options and relevant downstream patches. Stateful V4L2 and stateless Request API clients have different requirements. [Linux stateful interface](https://docs.kernel.org/userspace-api/media/v4l/dev-decoder.html), [stateless interface](https://docs.kernel.org/userspace-api/media/v4l/dev-stateless-decoder.html).
3. Play the exact local test asset. Save `chrome://gpu` capability information and the active player's `chrome://media-internals` decoder/platform fields, actual codec, dropped/total frames and errors. Capture native player's selected decoder separately. Chromium's documentation distinguishes advertised capability from the active decoder. [Chromium verification guidance](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/gpu/vaapi.md#verifying-vaapi-installation-and-usage).
4. Measure CPU, memory, temperature and presented/dropped frames against explicit software decode. Generic GPU-process decoder names alone do not identify the device; require a coherent driver/decoder trace or corresponding device-use evidence before labeling playback hardware accelerated. Do not infer it solely from lower CPU.

OWE 0.2.13 requests `hwdec=auto-safe` and reports the actual `hwdec-current` value. It uses libmpv's OpenGL rendering path, which remains in use even if decode falls back to software. Preserve that distinction in `owe render-status` results. Browser decode success does not establish OWE decode success, and vice versa. [OWE mpv implementation](https://github.com/omacom/owe/blob/v0.2.13/src/render/mpv.c), [OWE status interface](https://github.com/omacom/owe/blob/v0.2.13/README.md).

The `wf-recorder` fallback is also a separate encoding path. Treat 720p30 as the initial low-cost capture test and 1080p30 as a qualification workload, not a measured guarantee. Evaluate audio synchronization, recording duration, dropped frames and input responsiveness. Do not use the recorder itself to measure the unrecorded desktop's power or latency.

## Confirmed code defects and reproducible source gaps

These findings refer to the baseline files. Severity describes their impact on a Pi-first release, not a measured regression. Fixes are recommendations only.

### F1 — high: budgeted workloads escape the app-scope oomd policy

`bin/omarchy-pi-run:36` uses `systemd-run --user --scope` without `--slice=app.slice`. systemd-run's documented user default is the user manager's root slice, not `app.slice`; the Pi's policy only monitors descendants of `app.slice`. Moving a child into a new scope does not make it stay in the caller's application slice. The job still has its own high/max limits, but the advertised application-pressure escape path does not cover that new sibling scope. [Wrapper](../bin/omarchy-pi-run), [app policy](../default/systemd/user/app.slice.d/10-oomd.conf), [systemd-run slice semantics](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html#--slice=), [oomd candidate rules](https://www.freedesktop.org/software/systemd/man/latest/systemd-oomd.service.html).

Recommended fix: explicitly place the workload under `app.slice` or a deliberately monitored child slice. Keep `session.slice` and the compositor outside the candidate subtree. Extend the existing argv fixture to require placement, then inspect `/proc/<workload-pid>/cgroup`, `oomctl` and the live scope's `ControlGroup` on Linux. An argv fixture alone cannot prove active enforcement.

### F2 — high: native installs and updates have no guaranteed disk-backed staging

`build-packages-rpi4.sh:136`, `install-rpi4.sh:230` and `bin/omarchy-update-rpi4:57` use unconstrained `mktemp -d`. Without caller configuration that normally selects temporary storage, potentially tmpfs. The builder then stages the whole source and recipe work trees there. A source filter already excludes `.git`, `build/` and default image artifacts, which is good, but cannot make a tmpfs destination disk-backed. The Linux image factory itself has a useful external `TMPDIR` bind mount; this does not protect a normal update on the Pi. Its top-level `OMARCHY_IMAGE_WORK` also falls back to temporary storage. [Core builder](../build-packages-rpi4.sh), [installer](../install-rpi4.sh), [Pi updater](../bin/omarchy-update-rpi4), [image factory](../image/build-rpi4-image.sh).

Recommended fix: select a private per-user disk-backed workspace/cache by default, propagate it to recipe/core/update output paths, verify filesystem type, free bytes and inodes, and respect an explicit caller location. Use an SSD when available; do not silently require one. Clean only directories created by the invocation. `tmpfs` pages consume memory and can themselves be swapped, so moving compiler output there can turn a storage optimization into memory/reclaim pressure. [Linux tmpfs behavior](https://docs.kernel.org/filesystems/tmpfs.html).

### F3 — high: the first source build runs before Pi budget installation

`install-rpi4.sh:420` runs `install_arm_packages`, followed by core packaging; system/hardware setup runs only at line 425. The makepkg Pi drop-in is installed by that later setup. A bare ALARM install therefore does not receive the new defaults during the first required package builds. The pinned `ttfx` recipe calls Cargo without a job count; Cargo can use available logical CPUs when no job configuration exists. This makes the documented two-job 4GB policy incomplete at precisely the most memory-sensitive bootstrap stage. [Install order](../install-rpi4.sh), [apply leaf](../bin/omarchy-apply-pi-performance), [reviewed ttfx recipe](https://github.com/omacom/omarchy-pkgs/blob/99234a4fbb61b46225b2e9e560e114fbfebe8a95/pkgbuilds/ttfx/PKGBUILD), [Cargo parallelism](https://doc.rust-lang.org/cargo/commands/cargo-build.html#miscellaneous-options).

Recommended fix: apply/export the reviewed job and compression defaults from the checked-out source before any makepkg invocation. Do not require a graphical user manager in a chroot; use explicit bounded factory jobs and host resource limits there. Normal desktop updates should be placed in a budgeted workload or equivalent dedicated unit. Verify initial install, legacy updater bootstrap and normal update separately. The existing documented bootstrap exports job hints, but the general installer does not inherit that protection automatically.

### F4 — high for existing installs: boot guards ignore sections, includes and ordering

`install/hardware/raspberry-pi.sh:32` accepts a matching KMS line anywhere. A file containing `[pi5]` followed by `dtoverlay=vc4-kms-v3d` makes this guard succeed on a Pi 4 even though the section is inactive. When it finds such a line it also skips adding `[all]`, so newly appended settings can inherit an unrelated final filter. `set_config_value` rewrites all matching assignments without understanding their scope. The audio guard accepts an existing exact `dtparam=audio=on` even if a later `audio=off` wins. Multiple boot-config paths are chosen first-match, unlike the tuner's refusal of ambiguity. [Hardware leaf](../install/hardware/raspberry-pi.sh), [official conditional filters](https://www.raspberrypi.com/documentation/computers/config_txt.html#conditional-filtering).

Minimal source counterexample, not applied to a boot partition:

```ini
[pi5]
dtoverlay=vc4-kms-v3d
[all]
dtparam=audio=on
dtparam=audio=off
```

Both current presence guards report success; neither establishes the intended effective Pi 4 setting. Recommended fix: a backed-up, section-aware managed Pi 4 block with deterministic placement and explicit include/ambiguity handling. Avoid duplicate overlays or overwriting unrelated display/clock settings. Add inactive-section, include, duplicate audio, trailing-filter and ambiguous-path fixtures, followed by a real reboot/display/audio test. The existing image audit's line-presence checks need effective-configuration coverage too.

### F5 — medium/high on 4GB: static wallpapers decode at native size

`shell/Ui/BackgroundMedia.qml:34` leaves `sourceSize` zero for ordinary static wallpapers, and `shell/plugins/background/Background.qml:244` and `:267` do not constrain transition images. Their visual item bounds scale the displayed image but do not set the decoded storage limit. Native image-header inspection found the current first Tokyo Night image at 6016×3384 and `4-omakub.webp` at 6930×3960. At four bytes/pixel these correspond to 77.66MiB and 104.69MiB per full decoded image before extra copies, mipmaps and offscreen surfaces. These are arithmetic storage estimates, not process RSS observations. [Current image component](../shell/Ui/BackgroundMedia.qml), [current background](../shell/plugins/background/Background.qml), [Qt sourceSize semantics](https://doc.qt.io/qt-6/qml-qtquick-image.html#sourceSize-prop).

Upstream 4.5 already has a useful repair: physical-output-sized decodes, native-size probes to avoid upscaling small images, cleanup of prepared images, and corresponding changes in the intro covers. Retain that full behavior rather than carrying the old background component over wholesale. Test oversized, smaller-than-screen, portrait, multi-output and failed-load cases. [4.5 background implementation](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/shell/plugins/background/Background.qml), [4.5 media component](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/shell/Ui/BackgroundMedia.qml).

### F6 — medium: a failing GLX diagnostic suppresses the entire status report

`bin/omarchy-pi-status:80` assigns the result of `glxinfo -B | awk ...` under `set -euo pipefail`. If `glxinfo` exists but fails, the script exits before printing its otherwise useful native temperature, power and storage report. A Wayland-only session with no usable X display is a straightforward triggering condition; a `WAYLAND_DISPLAY` value alone satisfies the current guard. [Status helper](../bin/omarchy-pi-status).

A read-only reproduction sourced the actual helper with `glxinfo()` returning 1, `WAYLAND_DISPLAY` set, `DISPLAY` unset and nonexistent fixture sensor roots. Result: exit 1, zero bytes of stdout and no diagnostic report. No boot, user or system file was changed.

Recommended fix: handle renderer-query failure explicitly as unknown and continue with the rest of the report. Prefer a native EGL/Wayland query when available, and keep XWayland GLX output labeled as such. Add a fixture with a failing `glxinfo`. Separately strengthen `omarchy-pi-check`: its current V3D checkpoint checks a module/render node, not the actual compositor's renderer. Do not rename that checkpoint as proven hardware rendering until it tests the latter.

### F7 — low/medium: Mac factory sets the wrong Cargo job environment variable

`image/build-rpi4-image-macos.sh:85` sets `RUST_BUILD_JOBS`; Cargo's relevant variable is `CARGO_BUILD_JOBS`. The wrapper also constrains affinity with `taskset`, so this is not evidence that it uses every Mac core, but the intended per-build Cargo hint is missing. The wrapper has no explicit container memory ceiling and its default job count follows host CPU count, not competing projects or available VM memory. [Mac helper](../image/build-rpi4-image-macos.sh), [Cargo environment reference](https://doc.rust-lang.org/cargo/reference/environment-variables.html).

Recommended fix: use Cargo's documented variable and a coordinated, explicit CPU/memory/disk budget for factory runs. The generic image compressor's `xz -T0` also lacks a chosen memory budget. Bound compression threads/memory on the build host; this affects manufacturing resources, not installed desktop responsiveness. No Apple-platform build was requested or run here.

## Upgrade-specific traps

### U1 — high: 4.5 changes the ARM memory packaging contract

The currently pinned settings recipe `99234a4` deliberately omits the ARM zram and oomd defaults and strips reclaim tuning, which explains the fork's explicit Pi installation. Newer reviewed-recipe selection cannot assume that omission continues. Released 4.5 has `default/settings-runtime-profile`; current settings recipe `f6629ab` uses that marker to ship the memory tree on AArch64. This is a source-proven integration risk if that recipe is adopted, not a claim that the current Pi image already contains both policies. [Old recipe](https://github.com/omacom/omarchy-pkgs/blob/99234a4fbb61b46225b2e9e560e114fbfebe8a95/pkgbuilds/omarchy-settings/PKGBUILD), [new recipe](https://github.com/omacom/omarchy-pkgs/blob/f6629ab484fc9dc0336e5d2cbb29124f8b4af951/pkgbuilds/omarchy-settings/PKGBUILD), [released runtime marker](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/default/settings-runtime-profile).

Two precedence collisions require an explicit packaging decision:

- A vendor `90-omarchy.conf` is sorted after the Pi's `/etc/.../50-omarchy-pi.conf`, even though the latter is under `/etc`. It requests whole-RAM zram and zstd. Omitting `compression-algorithm` in an earlier file does not erase a later value. Current ALARM source config still has only the LZO zram backend enabled; unsupported zstd can make setup fail. Filter/mask the conflicting vendor file for Pi, or install the complete Pi configuration under the same basename in `/etc` so the vendor file is replaced as a whole. Preserve later administrator choices and verify the generated device. [zram-generator precedence and kernel-default behavior](https://github.com/systemd/zram-generator/blob/main/man/zram-generator.conf.md), [current ALARM config](https://github.com/archlinuxarm/PKGBUILDs/blob/748532cd1f8eea2d8f7a849d4f39ba5b74da60e1/core/linux-aarch64/config).
- `99-omarchy-sysctl.conf` sorts after `99-omarchy-pi-writeback.conf` because `s` sorts after `p`. If both are installed, upstream's 64MiB/256MiB dirty limits override Pi's 32MiB/128MiB, alongside swappiness 150, cache pressure 50, page-cluster 0, watermark changes and a 15-second writeback interval. A `99-` prefix alone does not establish precedence. Filter/select or explicitly override the intended keys without discarding unrelated network settings. Do not silently adopt all reclaim tuning as a measured Pi improvement. [4.5 sysctl file](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/etc/sysctl.d/99-omarchy-sysctl.conf), [sysctl ordering](https://www.freedesktop.org/software/systemd/man/latest/sysctl.d.html#Configuration%20Directories%20and%20Precedence).

The factory audit currently checks file presence and literal values. A candidate must also verify merged generator configuration, active swap/compressor, actual sysctls and the oomd cgroup tree after reboot. Successful package installation is not a substitute.

### U2 — preserve the Pi boot and user migration boundary

Upstream ARM support includes UEFI and Apple systems, not automatic Pi firmware/U-Boot support. Retain the Pi package filtering and platform routing when refreshing recipes; audit new hook-file names as well as the old ones. A new boot helper, runtime profile or migration must not switch kernels, introduce Limine hooks, enable hibernation/disk swap or reset an owner's monitor profile as a side effect of this desktop upgrade. Root filesystem snapshots are absent on the default ext4 image.

Keep new Pi defaults idempotent, installed on normal Pi core updates, and seeded for new users without re-running owner provisioning. Existing user changes need a targeted migration when necessary, with normal per-user completion tracking. Do not enable optional video, heavy local inference or dictation model downloads during migration. The 4.5 announcement introduces local dictation as an option; no Pi CPU/memory evidence justifies making that a Pi 4 background service.

## 4.5 visual and background costs

Some media support already exists at the baseline. Do not attribute every background cost to 4.5. The released target adds/refines intros, startup covers, the dock and a common reduced-motion path; it also includes memory and event-driven improvements worth keeping.

| Feature/path | Verified behavior in released source or its current engine | Pi 4 decision and measurement |
| --- | --- | --- |
| Normal windows and layers | Window/layer animations were already enabled; workspace animations, blur and shadows were already disabled. | Use the supported reduced-motion path for the conservative preset; compare normal animations under matched load before restoring them as a default. |
| Reduced motion | `no-animations.lua` disables compositor animation, blur and shadows. `Style.duration()` makes shell transitions zero-duration; shell refresh follows `configreloaded`. Intros check this setting as well as their own toggle. | Retain the coherent shell/compositor integration rather than adding many Pi-only animation flags. Check focus, notifications, lock and theme completion with zero duration. [Toggle](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/bin/omarchy-toggle-animations), [Style](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/shell/Commons/Style.qml). |
| Theme intros | Startup/theme switching can prepare and play video; startup/theme covers have ten-second fallback paths. The inactive-background handoff can run a 16ms timer launching `owe render-status` while waiting. | Seed intros disabled for both Pi 4 variants. Test disabled startup, failed media and rapid theme switching so there is no cover/poll loop left behind. The 16ms timer is conditional, not established idle polling. [Intro lifecycle](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/shell/services/BackgroundIntro.qml). |
| Continuous video | OWE requests hardware decode but can use software. Its default pauses for fullscreen coverage; occupied-workspace pausing is off. Warm/prepared contexts can remain for a minute. | Keep static wallpaper by default. Optional video initially qualifies at 720p30, then 1080p30. Verify pause, idle, DPMS and process/context release; one fullscreen window does not mean all outputs are covered. [OWE config](https://github.com/omacom/owe/blob/v0.2.13/config/config.toml), [engine lifecycle](https://github.com/omacom/owe/blob/v0.2.13/README.md). |
| Video lock feed | Lock can use a separate feed/render target; fallback when a module is absent exists in the baseline too. | Use stills for the conservative Pi profile. Lock security and recovery must work whether decode succeeds, fails or is absent. Qualify live feed separately from desktop video. |
| Dock | Single-shell plugin tracks windows and cached workspace modes. It displays on floating workspaces; hidden dock content retains textures. Its one-second launch timer runs only with pending launches. | Retain the capability and tiled-workspace default; do not claim it has zero resident cost or spins constantly. Measure hidden, floating, app grid, autohide, failed launch and multi-output cases. [Dock](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/shell/plugins/dock/Dock.qml), [dock window](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/shell/plugins/dock/DockWindow.qml). |
| Wallpaper upload/transition | 4.5 bounds decoded images and expires unused prepared frames, but transitions still need old/new images, masks and offscreen surfaces. | Merge those memory fixes. Test twenty switches and return-to-idle memory rather than claiming an exact RSS saving from pixel arithmetic. |
| Static background rendering | Existing source intentionally leaves `updatesEnabled=true` because parking the buffer was observed to cause black backgrounds. Quickshell documents potential savings from disabling it. | Do not reintroduce the known display failure for a theoretical saving. First profile actual frame/wakeup activity, then attempt a targeted lifecycle fix if needed. [Quickshell QsWindow](https://quickshell.org/docs/v0.3.2/types/Quickshell/QsWindow/#updatesEnabled). |
| Screensaver | Baseline `ttfx` requests 120fps, even on the intended 60Hz test display. The missing-renderer error loop has already been fixed. | Measure this as an idle-state cost. Test a 30fps cap or static idle presentation while preserving lock timing; neither is a measured improvement yet. [Screensaver](../bin/omarchy-screensaver). |

For scale, a tightly packed RGBA buffer is `width × height × 4`: 1920×1080 is 7.91MiB, 1920×1200 is 8.79MiB, and 3840×2160 is 31.64MiB. At 60fps, touching one such 1080p surface is about 475MiB/s; 4K is about 1.85GiB/s. These are arithmetic illustrations of why resolution and repeated full-screen effects matter, not measured bandwidth or a full compositor traffic model. Decoder planes, padding, tile layouts, compression, copies, multiple buffering and GPU caches change real usage. An 8GB Pi 4 has more RAM headroom; it does not receive a faster GPU or extra CPU cores.

## Defaults and experiments must stay distinct

The inherited CPU scaling, half-RAM zram, kernel-default compressor, app-only oomd, journal limits and 32MiB/128MiB writeback policy are defensible starting defaults. Their exact numbers have not been proved optimal. Retain them while fixing correctness and precedence, then compare one change at a time. Linux PSI distinguishes time with some stalled work from time with all non-idle work stalled; use that evidence alongside utilization. [PSI definitions](https://docs.kernel.org/accounting/psi.html).

Do not silently change swappiness, page-cluster, cache pressure, CMA, zram size/algorithm, the I/O scheduler, DVFS thresholds or clock limits. Current ALARM kernel source enables `schedutil`/`ondemand`, defaults to `performance`, and selects LZO-RLE for zram; running values still require inspection. Logical zram capacity is allocated on demand, with data-dependent compression and metadata cost. Monitor `orig_data_size`, `compr_data_size`, `mem_used_total`, incompressible pages and failures; do not assume a 3:1 ratio. Also inspect `zswap` so another compressor layer is not enabled inadvertently. [ALARM config snapshot](https://github.com/archlinuxarm/PKGBUILDs/blob/748532cd1f8eea2d8f7a849d4f39ba5b74da60e1/core/linux-aarch64/config), [Linux zram statistics](https://docs.kernel.org/admin-guide/blockdev/zram.html).

The current 300% CPU quota is a CPU-time allowance across cores, not physical-core reservation. MemoryHigh triggers reclaim/throttling; MemoryMax is a last ceiling and can kill a workload. Separate scopes have separate ceilings, so two jobs can still overcommit the board. GPU work, services launched through another manager and Docker daemon work are not automatically contained by the caller's scope. A memory-aware aggregate job admission policy is a future option; meanwhile document one heavy workload at a time and test it. [systemd resource controls](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html), [Linux cgroup v2 hierarchy](https://docs.kernel.org/admin-guide/cgroup-v2.html).

App-only oomd policy narrows that daemon's victim selection; it does not make the compositor immune to the kernel OOM killer or hardware/driver faults. Inspect ancestor policies as well as `app.slice`, because an ancestor configured for killing can broaden the candidate set.

Keep the stock supported governor/firmware protections. Check the governor before and after `omarchy-powerprofiles-init`, because that helper can choose `performance` when the daemon exposes it on AC. Whether Pi hardware exposes such a profile is unverified; source ordering alone does not prove a live conflict. Measure requested/current frequency and cooling under load; CPUFreq's `scaling_cur_freq` need not be an independent measurement of silicon frequency. [Linux CPUFreq interface](https://www.kernel.org/doc/html/latest/admin-guide/pm/cpufreq.html).

The tuner is explicitly opt-in, Pi 4-specific, backup-aware and guarded. Preserve those constraints; do not use its 1800/1900/2000 entries as validated presets. Confirmation checks kernel-exposed maximum capability, not sustained actual clocks or data integrity. Native `rpi_volt` alarm values are sampled firmware-derived state; the Linux driver polls about every two seconds, and the tuner checks every fifteen seconds. Keep kernel logs and available firmware history: a zero reading does not certify that no transient occurred. Do not require `vcgencmd` on a kernel without its interface. [Current tuner](../default/pi/tune.py), [Linux voltage sensor source](https://github.com/torvalds/linux/blob/master/drivers/hwmon/raspberrypi-hwmon.c).

Raspberry Pi documents progressive Arm throttling between 80°C and 85°C, with GPU throttling at 85°C. This protocol stops well below that. `arm_boost` support varies with Pi 4 revision; compare the same actual clock limits on both OSes and record if Pi OS enables a supported boost by default. Do not add manual voltage, GPU/SDRAM overclocking, `force_turbo`, raised thermal trips or `rpi-update` to the performance preset. [Thermal management](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#frequency-management-and-thermal-control), [clock/boost options](https://www.raspberrypi.com/documentation/computers/config_txt.html#arm_boost).

Keep ext4 durability and persistent logs. Disk-backed staging is a correctness/resource choice; it can increase media writes, so account for its latency and write volume rather than promise free speed. Check the actual block-device scheduler and cgroup support before promising `IOWeight=50` gives the desktop storage priority. BFQ offers latency-oriented proportional sharing with tradeoffs; it should be an A/B candidate, not a blanket scheduler change. Do not switch off barriers, use `data=writeback`, force frequent `drop_caches`, disable fsck, put browser/compiler caches on tmpfs by default or enable unbounded SD swap. [BFQ design](https://docs.kernel.org/block/bfq-iosched.html), [Linux VM/writeback definitions](https://docs.kernel.org/admin-guide/sysctl/vm.html).

A USB 3 SSD is a separate useful development profile, subject to enclosure, power and recovery qualification. Compare microSD against microSD and SSD against SSD across OSes; do not call a storage change an OS speedup. Inspect discard support before scheduling periodic trim; do not assume every USB bridge or card implements it. Leave continuous-discard and transport quirks alone unless an identified device needs them. [util-linux fstrim documentation](https://github.com/util-linux/util-linux/blob/master/sys-utils/fstrim.8.adoc).

## Quantitative qualification protocol

All numbers in this section are proposed engineering budgets chosen to keep an interactive margin on a four-core shared-memory machine. They are not Raspberry Pi guarantees, measured baselines or estimates of how much memory a particular browser will use. If a target is missed, retain the data and explain the limiting subsystem; do not adjust the workload or acceptance threshold after seeing the result.

### Equipment and test records

Required for each supported RAM variant:

- A real Pi 4 Model B with recorded board revision and actual `/proc/meminfo` capacity. A memory-limited 8GB board can help development but does not replace a real 4GB qualification. If only one variant is available, report support status for that variant explicitly.
- Reliable 5V/3A-class supply and suitable cable, consistent cooler/case/fan policy, and measured ambient temperature. Record fan speed policy and use an ambient window within ±2°C across a comparison. A supply meter or USB-C meter that can handle the supply path is strongly preferred for power comparisons. [Official power/peripheral requirements](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/).
- Keyboard, mouse, a known-good direct micro-HDMI cable and powered display. Primary mode is 1920×1080 at 60Hz, scale 1, SDR/8-bit. Run the NEC EA243WM at its tested 1920×1200/60 mode as a separate display cohort; do not mix these resolutions into one score. Verify actual mode and GTK scaling.
- A known-good working card kept untouched, spare matched media for candidates, a card reader and a second computer for offline recovery. Use at least 32GB target media with adequate free space; prefer 64GB or more for source/build qualification. Storage model/capacity/controller and filesystem fill must match within a comparison.
- Ethernet for baseline network-independent runs, speakers/headphones for playback verification, and any USB audio/Bluetooth input device used in real acceptance. Test Wi-Fi and Bluetooth separately; cameras and additional displays are extra qualification cohorts.
- For actual input-to-photon measurements, a repeatable input event with visible LED/photodiode timing and a camera at least 120fps, preferably 240fps. Without this or equivalent instrumentation, publish application timing/frame-cadence proxies with that limitation rather than an invented end-to-end latency number.

For SSD tests record the USB bridge, transport (`uas` or `usb-storage`), negotiated speed, power arrangement and disconnect errors. A serial console is useful for boot diagnostics, but preserve a physical recovery route even if SSH is available.

Every run needs a manifest with board/RAM, OS image hash, source and recipe commits, complete package versions, boot firmware/U-Boot/kernel identity, kernel command line, filesystem/mounts/free space, Mesa/Hyprland/Quickshell/Qt/Chromium/mpv/FFmpeg versions, active renderer, effective governor and frequency limits, display and scale, zram settings, oomd policy, storage, ambient temperature and test asset hashes. Record services and timers once after settling. Keep local identity/credentials out of shareable results.

### Four baselines, each answering a different question

| ID | Baseline | Purpose |
| --- | --- | --- |
| A | The maintainer's actual known-working published alpha image, identified by its download checksum and embedded manifest. | User-visible upgrade comparison, including original package stack differences. If unavailable, mark unavailable; do not reconstruct it from README wording. |
| B | Source `393f48c3` rebuilt against the same complete resolved ARM package set used for C, on spare media. | Isolate desktop/source changes from rolling kernel/browser changes. Preserve signed artifacts and package lists; do not create a partial system downgrade to force a match. |
| C | Released 4.5 source plus reviewed Pi fixes, exact candidate commit and image manifest. | Candidate qualification, on both 4GB and 8GB. |
| D | Current supported official 64-bit Raspberry Pi OS Desktop image, exact image date/hash and updates recorded. | Whole-system user-experience/parity comparison. Its different compositor, kernel and patched media stack are part of the result, so this comparison cannot attribute a change to one desktop component. |

Use each physical board against itself. Match power, cooler, display, storage model/fill, clocks and workload. Where practical run B→C→B and C→D→C to detect drift; reuse the same test media only after imaging/backing it up, or counterbalance matched media to quantify card variability. Record supported firmware boost differences rather than silently overclocking one side to manufacture equality. Do not compare a 4GB A run against an 8GB C run.

If B cannot run against C's package set because of compositor/API incompatibility, mark that controlled comparison unavailable and use A with the package-stack differences disclosed. Do not force an invalid dependency mix or describe a rolling-system comparison as isolated desktop evidence.

For repeated tests, warm up once, then run five measured repetitions per workload/configuration. Report median, minimum/maximum and IQR, with failures and exclusions retained. Separate reboot-cold, first-launch and warm/incremental runs. Reboot for cold-system runs; do not repeatedly use `drop_caches` to simulate a cold desktop. Begin measured runs after five minutes of settling and at a comparable starting temperature within ±3°C; let thermal conditions recover between workloads. At least two independent cold boots should reproduce the main result. Order optional tuning A/B tests so a warming board does not always penalize the second setting.

### Memory and workload envelopes

Let `M` be actual `MemTotal` converted from KiB to MiB, not the nominal number printed on the board. The existing wrapper's thresholds are `0.50M` high and `0.65M` maximum; logical zram is approximately `0.50M`. For idealized 4096/8192MiB values these are respectively 2048/4096MiB high, 2662/5325MiB maximum, and 2048/4096MiB logical swap. Actual values will be lower where firmware/kernel reservations reduce Linux-visible RAM.

Retain that existing profile for an isolated heavy-job comparison with browser workloads closed. For the mixed desktop protocol, use the following deliberately smaller candidate envelope. It requires a test unit or a reviewed configurable wrapper; these limits are not already implemented by `omarchy pi run`.

| Concurrent use | 4GB planning share of M | Idealized 4GB example | 8GB planning share of M | Idealized 8GB example |
| --- | --- | --- | --- | --- |
| Kernel, resident services, compositor, shell and graphics working set | 22.5% | 922MiB | 17.5% | 1434MiB |
| Fixed browser workload | 20% | 819MiB | 25% | 2048MiB |
| Two terminals, Neovim and one hosted-agent CLI/replay | 7.5% | 307MiB | 7.5% | 614MiB |
| One build, hard ceiling | 37.5% | 1536MiB | 37.5% | 3072MiB |
| Interactive/reclaim margin | 12.5% | 512MiB | 12.5% | 1024MiB |
| Build reclaim threshold, inside its ceiling above | 25% | 1024MiB | 30% | 2458MiB |

The first five rows sum to M as a planning model. They are not a valid sum of overlapping RSS, PSS, cgroup and GPU counters. Account shared pages once, use cgroup `memory.current`/`memory.peak` for jobs, sum PSS for comparable process cohorts, and reconcile with MemAvailable, Shmem, kernel/slab and GPU/driver observations. Zram's actual compressed storage is part of the physical budget, never another full RAM allowance. A process's logical swapped bytes and the zram device's physical compressed bytes must not both be counted as resident RAM.

Use one build at a time, at most two jobs on 4GB and three on 8GB, falling back to one below 2GiB available. These are starting ceilings; a single linker can exceed the memory budget. Run 4GB and 8GB through the same four-tab common workload first. Then add an eight-tab development workload on 8GB. The four fixed tabs should be checksum-pinned local documentation, code view, editor and dashboard fixtures; the browser/video test adds one declared clip. Keep the browser's real sandbox and normal security configuration. Do not interpret “four tabs” as a universal cap independent of page content.

A deterministic replay of agent terminal output separates UI performance from provider/network latency. Perform a live hosted-agent login/request smoke test separately. Downloading local model weights, local speech models or large inference services is outside the conservative workload budget.

### Verify effective policy before load

On Omarchy, run the repository's board check and retain read-only reports. On Raspberry Pi OS, collect equivalent native `/proc`, `/sys`, package, service and graphics evidence without installing Omarchy or transplanting its global policy. Match job counts for throughput comparisons; label constrained-scope runs separately from each OS's default experience. Inspect effective state, not just installed files:

```bash
omarchy-pi-check
omarchy pi report --json
omarchy pi tune status
omarchy-pi-display status
zramctl
swapon --show --bytes
systemd-analyze cat-config systemd/zram-generator.conf
systemd-analyze cat-config systemd/oomd.conf
systemctl --user show app.slice -p ManagedOOMMemoryPressure -p ManagedOOMSwap
oomctl
systemctl --failed
systemctl --user --failed
findmnt -T /tmp
findmnt -T /var/tmp
sysctl vm.dirty_background_bytes vm.dirty_bytes vm.swappiness vm.page-cluster
```

Collect the active zram compressor's bracketed selection and `mm_stat`, generated swap-unit state, oomd service state and cgroup controllers, `/sys/module/zswap/parameters/enabled` if present, actual CPU policy files and active block scheduler. `systemd-analyze cat-config` describes source configuration; cross-check active sysfs state because reboot/reinitialization may be pending. Missing optional tools or sensors stay explicitly unavailable, never healthy by default.

For scope inspection, a harmless job can print its own PID and `/proc/self/cgroup` while alive. Check its corresponding live user unit for `Slice`, `ControlGroup`, CPU quota/weights and memory high/max; inspect `cpu.max`, `memory.high`, `memory.max`, `memory.events` and supported I/O controls. Verify that the compositor and shell are in the expected session hierarchy. Do not assume `systemd-run` success means every controller has an effective limit. A scope's memory cap does not cap GPU time or a separately activated service.

In a disposable Linux test environment, first prove hard-limit behavior using a small test-only cap, for example 128MiB high/192MiB max and a bounded allocator attempting 256MiB. Distinguish a local cgroup OOM from an oomd action. Validate oomd candidate wiring with separate, deliberately small disposable slice tests and inspect its selected victims. Do not induce whole-board memory exhaustion to demonstrate a protective policy. On the actual Pi, inspect normal scope wiring first and stop on sustained pressure rather than sacrificing the session to a stress test.

### Workload matrix

| Test | Fixed workload and duration | Measurements | Proposed gate |
| --- | --- | --- | --- |
| Boot/provisioning | Five normal cold boots, with first-owner setup measured separately; two power cycles among them. | Power-on-to-visible login/usable desktop with an external timer, graphical startup logs, root expansion/provisioning status, native mode, renderer and input. | 5/5 usable, no boot repair, root fully grown, no config errors or recurring crash loop. Candidate median time no more than 10% worse than matched B unless a documented reliability fix explains it. |
| Settled idle | Ten minutes after settling, default bar, static wallpaper, no open panels or builds; repeat once after normal idle/lock. | CPU time, MemAvailable, PSS/cgroup memory, PSI, temperature, optional wall energy, wakeups and block writes. | Within OS/desktop memory envelope; desktop cohort median CPU at most 10% of one core (2.5% of four-core capacity), no persistent busy loop, memory-full PSI average below 0.1%. Investigate any candidate idle power rise over 5% beyond meter/run noise. |
| Idle-state transitions | Defaults through screensaver at 150 seconds, lock at 300 seconds, DPMS if configured; five wake/unlock cycles including one after 30 minutes idle. | Physical display, lock correctness, CPU/power before/during/after, clock/fan behavior, startup/OWE timers, failed services. | 5/5 recovery with input and audio intact; no unexpected persistent animation/decoder load. Screensaver power is reported separately from desktop idle. |
| Interactive common workload | Four fixed tabs, two terminals, Neovim; 100 predetermined focus/workspace/menu/notification operations, then ten minutes scripted scrolling and typing. | End-to-end input latency where instrumented, presented-frame cadence, completion/focus correctness, cohort PSS, memory/I/O PSI. | No stuck focus/black surfaces; p95 input-to-photon at most 100ms and no more than 10% worse than B beyond instrument noise. During active motion, p95 presented-frame interval at most 33.3ms and p99 at most 50ms at 60Hz. |
| 4GB mixed development | The common workload plus one fixed Rust or C build/rebuild workload for 30 minutes, within the smaller mixed budget. | Input/frame metrics plus job wall time, CPU, peak memory, `memory.events`, PSI, frequency and temperature. | MemAvailable normally at least 12.5% of M; no OOM/session loss; no memory-full PSI `avg10 > 1%` for 30 seconds; interaction gates still met. Record throughput lost to budgeting separately. |
| 8GB mixed development | Same common run, then eight fixed tabs plus the editor/hosted-agent replay and one build for 30 minutes. | Same, including additional tab cost and available margin. | Same percentage headroom/pressure gates with the 8GB envelope; no assertion of a CPU/GPU speed increase from extra RAM. |
| Fixed build throughput | Cached dependency builds of a locked small Rust tree (the reviewed ttfx source is suitable) and a fixed C/Ninja tree (for example the selected OWE version). Fresh build directory vs incremental run; `-j1`, `-j2`, and `-j3` only on 8GB. | Exact source/lockfile/compiler flags, wall/CPU time, cgroup peak, pressure, frequency and block writes. | Successful output; matched-job candidate median within 10% of B outside observed variation. Linker peak fits the chosen envelope. No dependency fetch mixed into compile timing. |
| Real core update/packaging | One rebuild of the four ported core packages on spare media, then an existing-install update and a separately tested original-image bootstrap. | Staging filesystem/free space/inodes, peak memory, compress time, writes, installed receipt, optional app failures and UI responsiveness. | Disk-backed staging verified; budget present before first recipe; failed build remains retryable; no owner/display/clock reset; completed update boots and passes policy checks. |
| Browser/player media | Local H.264 720p30, 1080p30, 1080p60; HEVC Main 1080p30 and optional 4K; VP9/AV1 as explicit software/fallback probes. Three-minute clips, five runs for supported modes. | Codec/profile/bit depth/bitrate, active decoder/device path, CPU, dropped/total frames, PSS, audio sync, temperature and PSI. | Core H.264 720p30/1080p30 playback: under 1% dropped frames after a declared startup exclusion, no persistent A/V drift over 100ms or pressure violation. Higher modes get independent support results; hardware decode is claimed only with the four-step proof. |
| Wallpaper/theme/dock | Twenty switches including oversized images; ten-minute optional 720p30 video then static; intro off/on separately; hidden dock, floating dock, app grid and failed launch. | Memory peaks/recovery, shell/OWE CPU, frame cadence, active decode, pause on all-output fullscreen/lock/DPMS, timer/process release. | Default static path meets idle/interaction gates. After five minutes idle, no monotonic memory growth and at most 64MiB unexplained cohort growth vs the same initial state; retain legitimate cache separately. No stuck startup cover or repeating status process. |
| Storage contention | Small scratch-file build/extract workload plus browser typing; optional bounded 4KiB random-read and limited-write test on a disposable 256MiB file. | Application latency, I/O PSI, block latency/queue data where available, filesystem errors, total bytes written. | No I/O error/disconnect; no I/O-full PSI `avg10 > 5%` for 30 seconds; interaction gates hold. Limit optional writes to 256MiB per measured run, not an unbounded time-based write loop. |
| Capture/audio | Two-minute 720p30 capture and separate 1080p30 trial, fixed moving content and audio; play back saved result. | Dropped frames, timestamp/audio drift, encoder identity, file integrity, UI latency, heat. | 720p30 baseline usable; each higher capture mode explicitly qualified. Capture result must be visually/audibly inspected. Exclude capture overhead from unrecorded performance numbers. |
| Thermal/reliability soak | Sixty-minute mixed normal workload at stock policy, then ten minutes recovery; five monitor power/hotplug and lock/wake cycles, plus Wi-Fi/Bluetooth/audio/USB checks. | Native sensors, logs, crash/OOM/GPU reset/USB/MMC errors, frequency, pressure, recovery and data checksums. | Zero crashes, OOMs, corruption or unexplained GPU resets; zero observed undervoltage; no thermal throttling; return within 5°C of pre-run temperature within ten minutes under matched ambient conditions. |

These relative performance gates apply most cleanly to B versus C. Report A/D comparisons separately when package versions, supported boost, browser patches or desktop behavior differ. A materially worse media path than D prevents a blanket Pi OS parity claim even if terminal/build tests pass. Missing frame/input instruments prevent a quantitative latency claim; they do not license substituting the display refresh setting for measured frames.

For frame cadence, use actual presentation feedback or an appropriately validated external camera method during active motion. Idle applications deliberately do not present continuously. Qt render timing is useful diagnostic evidence for shell surfaces, not a complete desktop/input-to-photon measurement; instrumented debug runs must be labeled. For browser video, `getVideoPlaybackQuality()` can provide total/dropped frame counts for a controlled page, paired with decoder and audio evidence. Keep network-delivered video, online services and provider responses as separate experience tests with network conditions recorded.

### Sampling, abort and recovery rules

Use one lightweight collector with monotonic timestamps. Sample `/proc/pressure/*` totals, MemAvailable/Shmem, CPU jiffies, load, requested frequency and relevant cgroup counters every second; native voltage/temperature every two seconds; process PSS and zram statistics every five seconds. Take full reports before/after, not once a second. Collect `vmstat 1` if available, with a matched instrumentation overhead check. CPU usage should state whether 100% means one core; for four cores aggregate capacity is 400% under that convention. For a custom PSI window, stall fraction is `delta(total_us) / elapsed_us`, not the raw accumulated counter. Do not use system-level CPU `full` as a busy-time metric.

Start load below 70°C with no active voltage alarm. At 70°C warn and inspect the temperature trend; at 75°C stop the test workload, save diagnostics, and cool down. Stop immediately for voltage alarm, storage errors, repeated GPU reset, display loss, corrupted output, an OOM or the sustained PSI/headroom violations above. Unknown thermal/power health blocks unattended load testing; it does not make read-only diagnostics fail. Do not increase thermal trips to pass a test. The existing microbenchmark's 70/75°C safeguards are useful, but its two SHA-256 workers are not a substitute for this mixed suite.

At 60Hz a frame period is 16.67ms; the proposed frame gates permit occasional missed refreshes without accepting long freezes. At 120fps camera capture quantization is about 8.33ms and at 240fps about 4.17ms: report that measurement resolution, sample count and input-marker method with p95 results. Apparent differences smaller than the instrument's resolution or run-to-run spread are inconclusive.

After each run, close only the applications started by the test, return to the same theme/display mode, stop the test scope, and verify that no test process or temporary policy remains. Do not kill processes by broad names. Keep the current dynamic governor and normal cache recovery; record any reboot used to establish a fresh baseline. Inspect audio and the physical desktop after recovery rather than relying only on service state.

### Result bundle and release gates

Recommended future output layout, not created by this audit:

```text
results/pi4-performance/<ram-and-board>/<image-id>/<run-id>/
  manifest.json
  policy-before.txt
  pi-report-before.json
  samples.csv
  cgroups.json
  build-or-player-result.json
  pi-report-after.json
  errors.txt
  visual/
  summary.md
```

Each summary should state tested mode, units, repetitions, medians/spread, failures, raw-log paths, whether decoder use is proven, and whether input/frame metrics are direct measurements or proxies. Retain local test-fixture source and checksums. Screenshots/short recordings belong with functional visual verification; performance measurements should use external capture when local recording would perturb them. Publish no combined “Pi score” that hides a 4GB failure behind an 8GB success.

Promotion requires all of the following:

1. Fix/review F1–F4 and validate U1/U2 packaging before building a candidate; preserve and integrate F5's upstream fix. Resolve the status diagnostic and bound factory resources as part of the supported workflow.
2. Run focused source tests for Pi performance, tuning, display, firmware, detection, update safety, source staging and image audit, plus relevant 4.5 background/intro/dock/reduced-motion tests. On macOS, clearly report any Linux-only skips; run those on a disposable native ARM64 Linux environment. No fixture result is hardware evidence.
3. Build and inspect final packages/image on a coordinated native ARM64 Linux host. Inspect payload/architecture/provenance, effective configuration and boot-hook filtering. The existing parser check is valuable but does not emulate Pi graphics.
4. Pass physical boot, HDMI/rendering/input, audio/network/Bluetooth/storage and lock/wake on each claimed RAM variant. Run the default mixed suite on both. A missing Pi 4 variant remains unqualified.
5. Qualify video/intros/live lock feed and extra displays separately before enabling them by default or advertising those modes. List any media gap against Pi OS honestly. No universal “faster than Pi OS” statement without declared workload results.

## Rollback and experiment isolation

Before system/package testing, save a verified whole-card/drive image, the complete FAT boot partition, `/etc/fstab`, package list, exact cached packages or an intact known-working image, `/etc/omarchy-rpi4.conf`, the installed source receipt, relevant Pi policy drop-ins and user Hyprland/Omarchy state. Keep owner credentials protected; share only redacted evidence. A Git checkout reset is not a rollback for a kernel, firmware or package transaction.

Use spare media for new images and any vendor-kernel variant. Keep the known-working card untouched. The default ext4 image has no automatic Snapper recovery. A failed package transaction must be diagnosed/retried; do not reboot into a knowingly incomplete kernel/initramfs set. A package rollback needs a coherent matching package set and boot files, not one arbitrarily downgraded library.

For visual experiments, retain the exact prior mode/theme/toggle configuration, include a timed mode revert, and keep console/SSH recovery available. Restore only test-owned changes; respect later owner edits. The NEC helper's backup/reset behavior is useful but cannot recover a crashed compositor or repair EDID/audio on its own. If reduced motion is being seeded for new Pi users, do not replace an existing user's complete monitor/look-and-feel configuration to achieve it.

For zram or memory-policy trials, close the workload, restore the selected configuration and reboot into it. Do not `swapoff` a populated zram device under memory pressure. After reboot verify active swap, compressor, sysctls, oomd and scope placement again. For governor trials, record/restore the prior policy and the CPU-policy service's enabled/masked state; do not unmask a deliberate owner choice.

No clock trial is part of release qualification. If testing an existing managed trial for another reason, use the documented tuner restore flow, retaining `config.txt.omarchy-before-tune`. An unbootable board needs offline boot-file or whole-media restoration; a successful runtime cap cannot guarantee filesystem integrity. Firmware, kernel or governor changes must not overwrite that recovery state silently.

## Pi 5 deferred boundary

No Pi 5 is available and this audit establishes no Pi 5 support. The generic `omarchy-hw-raspberry-pi` helper matches more than Pi 4; that must not be mistaken for a support declaration. Keep the installer/qualification boundary at Pi 4 Model B 4GB/8GB and keep unsupported overrides explicitly experimental. The clock tuner already restricts itself to Pi 4.

A future Pi 5 4GB+ effort needs its own board identity, firmware/bootloader/kernel/DTB profile, graphics and decoder stack, power/cooling, USB/PCIe/NVMe storage, display modes and suspend/lock/wake validation. Reuse the test harness and memory-accounting principles, not Pi 4 clock, modifier, thermal, media or boot assumptions. In particular, V3D generation and firmware-memory behavior differ; more recent ARM support elsewhere in upstream Omarchy supplies neither Pi 5 boot validation nor a Pi 4 performance result. [Mesa hardware generations](https://docs.mesa3d.org/drivers/v3d.html), [Raspberry Pi firmware-memory distinction](https://www.raspberrypi.com/documentation/computers/legacy_config_txt.html#gpu_mem).

## Implementation handoff

Suggested order for the parent upgrade task:

1. Fix workload slice placement, disk-backed staging and initial-build budget propagation; add focused behavioral fixtures with small disposable limits for enforcement tests.
2. Select a compatible reviewed 4.5 recipe snapshot and resolve zram/sysctl/boot-file ownership together. Do not advance the recipe pin merely because its version label says 4.5: the currently inspected recipe's own source commit differs from the released tag, while the Pi builder uses a local source override.
3. Integrate released background decoding, common reduced motion and event-driven shell behavior. Seed the conservative Pi profile only where defaults are appropriate; retain dock/app access and owner customization.
4. Build a candidate on a resource-budgeted native ARM64 Linux host, inspect its contents, then perform the physical protocol on spare Pi media. Keep vendor-kernel work as a separately named candidate until independently booted and measured.
5. Fill the result bundle and classify each 4GB/8GB feature as passed, failed or untested. Pi OS parity, 4.5 end-to-end support and Pi 5 remain unclaimed until their own gates pass.

This report's completed deliverable is the source/research audit and actionable qualification protocol. The upgrade implementation, image assembly and physical measurements remain work for the parent task.
