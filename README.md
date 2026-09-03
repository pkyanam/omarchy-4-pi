<div align="center">
  <img src="docs/assets/hero-placeholder.svg" alt="Omarchy 4 Pi — Quattro on Raspberry Pi 4" width="100%">

  # Omarchy 4 Pi

  **The delightfully opinionated Omarchy Quattro desktop, remixed for Raspberry Pi 4.**

  [![Project status: alpha](https://img.shields.io/badge/status-alpha-f5a97f?style=for-the-badge)](#project-status)
  [![Pi port checks](https://github.com/pkyanam/omarchy-4-pi/actions/workflows/pi-checks.yml/badge.svg)](https://github.com/pkyanam/omarchy-4-pi/actions/workflows/pi-checks.yml)
  [![Latest release](https://img.shields.io/github/v/release/pkyanam/omarchy-4-pi?include_prereleases&style=for-the-badge)](https://github.com/pkyanam/omarchy-4-pi/releases)
  [![Target: Raspberry Pi 4](https://img.shields.io/badge/target-Raspberry_Pi_4-c51a4a?style=for-the-badge&logo=raspberrypi&logoColor=white)](#what-you-need)
  [![Architecture: ARM64](https://img.shields.io/badge/architecture-ARM64-1793d1?style=for-the-badge&logo=archlinux&logoColor=white)](#how-it-works)
  [![License: MIT](https://img.shields.io/badge/license-MIT-a6da95?style=for-the-badge)](LICENSE)

  *Tiny board. Big desktop energy.*
</div>

> [!IMPORTANT]
> This is an independent community port and is not an official Omarchy or Raspberry Pi product. The first image now boots to Omarchy's HDMI setup splash on a real Pi 4; owner setup, Quattro, and V3D verification are still in progress. Treat artifacts as alpha until the [hardware checklist](https://github.com/pkyanam/omarchy-4-pi/issues/1) is green.

## The destination

Pick an image in Raspberry Pi Imager, flash it, boot the Pi, answer a few friendly setup questions, and land in the full Omarchy 4 “Quattro” desktop: Hyprland, the Quickshell bar and launcher, themes, hotkeys, Chromium, terminal tooling, and the unusually pleasant details that make Omarchy feel like Omarchy.

The finished release flow will look like this:

```text
Raspberry Pi Imager → Choose OS → Use custom → omarchy-4-pi-*.img.xz → Write → Boot → ✨
```

Each GitHub release is intended to provide a compressed flashable image, SHA-256 checksum, build manifest, and human-readable release notes. The same image must also be reproducible from this repository.

## Project status

| Piece | Status | Notes |
|---|---:|---|
| Quattro ARM64 package audit | ✅ | Hyprland and Quickshell are available in Arch Linux ARM |
| Pi 4 hardware detection | ✅ | Device-tree based, with focused tests |
| VC4/V3D graphics setup | ✅ | Full KMS, Broadcom Vulkan, Aquamarine compatibility setting |
| ARM-safe package lifecycle | ✅ | Arch Linux ARM mirrors survive install, refresh, and update flows |
| In-place Arch Linux ARM installer | 🧪 | Implemented; real-hardware soak testing pending |
| Reproducible `.img` builder | ✅ | Native ARM64 builds enforce signed-base, boot-payload, package-architecture, identity, Hyprland config, filesystem, manifest, and checksum gates |
| Real Pi 4 boot + HDMI splash | ✅ | Alpha image reached Omarchy's first-boot greeter on hardware |
| Automatic storage expansion | ✅ | Root partition and ext4 filesystem grow before onboarding; failure keeps provisioning safely armed for retry |
| First-boot owner setup | 🧪 | Greeter verified on real Pi 4; corrected unattended path is image-audited and ready for hardware testing |
| Quattro desktop + V3D on hardware | 🧪 | Pending completion of the first owner setup |
| Raspberry Pi Imager metadata | ✅ | Catalog generator emits exact compressed and extracted SHA-256 hashes |
| Imager 2.x unattended setup | 🧪 | The `alpha.5` keymap bug is fixed; corrected `alpha.6` passed its post-tag 75-check mounted-image audit |
| Prebuilt image prerelease | 🧪 | [`v0.1.0-alpha.6`](https://github.com/pkyanam/omarchy-4-pi/releases/tag/v0.1.0-alpha.6) is published and verified; owner/desktop hardware testing remains |
| Public Imager catalog URL | ✅ | The immutable [`alpha.6` catalog](https://github.com/pkyanam/omarchy-4-pi/releases/download/v0.1.0-alpha.6/os-list.json) is live |

Legend: ✅ implemented and locally verified · 🧪 ready for hardware testing · 🚧 being built · ⏳ queued

## What you need

- Raspberry Pi 4 Model B — the 8 GB model is nicest, 4 GB is supported as a target
- 32 GB or larger microSD card; a USB 3 SSD is strongly recommended
- The official-quality 5 V / 3 A power supply
- HDMI display and network access; use a keyboard for interactive setup or Imager 2.0.11+ for keyboard-free setup
- A taste for tiling windows on improbably small computers

## Try it today

### Flash `alpha.6`

> [!WARNING]
> Do not use `alpha.5` for keyboard-free setup. Its unattended branch omits the staged keymap argument and falls back to **Press Return to Start Setup**. Use the corrected, independently audited [`alpha.6` prerelease](https://github.com/pkyanam/omarchy-4-pi/releases/tag/v0.1.0-alpha.6).

For an HDMI-only Pi, use Raspberry Pi Imager 2.0.11 or newer and open the release's public catalog on macOS:

```bash
open -n -a "/Applications/Raspberry Pi Imager.app" --args --repo \
  "https://github.com/pkyanam/omarchy-4-pi/releases/download/v0.1.0-alpha.6/os-list.json"
```

Select **Omarchy 4 Pi**, then fill in the account, locale, and any Wi-Fi or SSH settings before writing. Complete account settings let the Pi provision the owner and continue without waiting at **Press Return to Start Setup**. The catalog records exact compressed and extracted sizes and SHA-256 hashes, so Imager verifies the download before flashing.

If you enable SSH, the Pi advertises the hostname chosen in Imager over mDNS. From a Mac on the same network, connect without hunting for its IP address:

```bash
ssh YOUR_USERNAME@YOUR_HOSTNAME.local
```

The default hostname is `omarchy`, so that is normally `ssh YOUR_USERNAME@omarchy.local`. If `.local` discovery is filtered by the network, find the Pi in the router's client list and use its IP address instead.

The release image is [`omarchy-4-pi-20260903-826c5daa-minimal.img.xz`](https://github.com/pkyanam/omarchy-4-pi/releases/download/v0.1.0-alpha.6/omarchy-4-pi-20260903-826c5daa-minimal.img.xz) (2,075,195,288 bytes). Its SHA-256 is `a19456f99cbc441be165f44fdca4facde517bcca8775a7cb8860a0ccbe460f49`; the attached [checksum file](https://github.com/pkyanam/omarchy-4-pi/releases/download/v0.1.0-alpha.6/omarchy-4-pi-20260903-826c5daa-minimal.img.xz.sha256), GitHub asset digest, and Imager catalog all agree.

> [!NOTE]
> If an earlier image is already waiting at **Press Return to Start Setup** and no keyboard is attached, it cannot consume settings retroactively. Reflash the completed `alpha.6` image through the catalog above and complete Imager's account section before writing the card.

If you already downloaded the image on macOS, the repository helper serves it only to `127.0.0.1` while Imager is open and provides the same customization flow:

```bash
image/open-in-rpi-imager-macos.sh "/path/to/omarchy-4-pi-*-minimal.img.xz"
```

Keep that terminal open until the write finishes; closing Imager shuts down the loopback server automatically. Imager 2.0.10 and older prune `rpi-preseed` catalog entries, so the helper stops with a clear upgrade message instead of silently falling back to an uncustomized flash.

### Build a flashable image

The supported factory runs on an aarch64 Linux host with loop-device support. The easiest route is **Actions → Build Raspberry Pi image → Run workflow** in this repository; it uses GitHub's native ARM64 runner and returns an `.img.xz`, checksum, build manifest, mounted-root audit report, and Raspberry Pi Imager catalog as one workflow artifact.

To build locally on an ARM64 Linux machine:

```bash
sudo apt-get install libarchive-tools dosfstools e2fsprogs gnupg parted rsync xz-utils zerofree
sudo image/build-rpi4-image.sh --minimal
```

On an Apple-silicon Mac with Docker Desktop running, use the native ARM64 helper:

```bash
image/build-rpi4-image-macos.sh --minimal
```

It uses all but two Mac cores by default, keeps build I/O inside Docker's Linux filesystem, and selects fast xz compression. Set `OMARCHY_LOCAL_CPUS=8` to choose an explicit core count or `OMARCHY_XZ_PRESET=-6` for a smaller, slower artifact.

Artifacts land in `build/image/`. In Raspberry Pi Imager, choose **Use custom**, select the `.img.xz`, and write it to a 32 GB or larger card/SSD. On first boot, Omarchy expands the filesystem, asks you to create the owner account, and then opens Quattro. The factory removes Arch Linux ARM's default `alarm` account and locks the default root password before compression.

Images built from current `main` also understand Raspberry Pi Imager 2.x's `rpi-preseed` format. When the image is selected through an Imager catalog or the local manifest helper above, the customization wizard can securely supply a pre-hashed owner password, hostname, keyboard, timezone, Wi-Fi, and optional SSH access; complete settings skip the keyboard-driven owner form. Imager intentionally treats a bare **Use custom** image as non-customizable, so that path continues to show Omarchy's on-screen setup. See the [official Imager format documentation](https://github.com/raspberrypi/rpi-imager/blob/main/doc/os_customisation_formats.md).

`--full` adds the optional ARM-buildable Omarchy applications. It is slower and considerably larger; the minimal image already contains the complete desktop shell, browser, terminal, file manager, developer tools, theming, and core commands.

Routine builds use balanced multithreaded xz compression. Set `OMARCHY_XZ_PRESET=-9e` (or choose **maximum** in Actions) when a release needs the smallest possible download and extra build time is acceptable.

### Install onto an existing Arch Linux ARM system

Start with the official [Arch Linux ARM aarch64 Raspberry Pi 4 root filesystem](https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4), create a regular sudo-capable user, then run:

```bash
git clone https://github.com/pkyanam/omarchy-4-pi.git ~/omarchy-4-pi
cd ~/omarchy-4-pi
./install-rpi4.sh
```

For the complete Quattro shell without compiling the optional application bundle:

```bash
./install-rpi4.sh --minimal
```

The full walkthrough, verification commands, update behavior, limitations, and black-screen recovery notes live in [the Raspberry Pi 4 install guide](docs/raspberry-pi-4.md).

## How it works

Upstream Omarchy Quattro is package-backed and its ISO follows an x86_64 boot path. The Omarchy packages themselves are architecture-independent, but the public stable package repository currently has no aarch64 tree. This project bridges that gap without pretending the Pi is a PC:

```text
Arch Linux ARM aarch64 base
├── Raspberry Pi firmware + U-Boot boot path (kept intact)
├── VC4 KMS + V3D Mesa graphics
├── Hyprland + Quickshell from Arch Linux ARM
├── ARM-compatible apps from upstream Omarchy PKGBUILDs
└── Omarchy Quattro core, built locally without Limine dependencies
```

The port also teaches the normal Omarchy update, channel, snapshot, and package-refresh commands about the Pi. That matters: a desktop that boots once but replaces its ARM repositories with x86 mirrors during the first update is not a port; it is a very elaborate practical joke.

## Pi-friendly quality of life

The image roadmap includes more than “make it boot”:

- zram tuned for the Pi's smaller memory ceiling
- first-boot user, locale, timezone, Wi-Fi, and hostname setup
- Raspberry Pi Imager 2.x unattended setup without a factory account or plaintext owner password
- checksum-verified ARM64 Node.js staged for offline first-owner finalization
- SSH opt-in with a clear security posture
- grow the root filesystem automatically on first boot
- power/thermal/undervoltage status surfaced in diagnostics
- sensible 1080p defaults with expensive blur and animation options documented
- CPU-friendly `wf-recorder` capture at 30 fps
- SD-card-write reduction for logs, caches, and browser churn
- safe headless recovery when the graphical session cannot start
- build manifests that record every upstream commit and package version

Suggestions are welcome—especially the small, obvious-in-retrospect touches that make a Pi feel like an appliance instead of a weekend of Linux archaeology.

## Build philosophy

The image builder is boring in the best way:

1. Download the official Arch Linux ARM Raspberry Pi 4 root filesystem and detached signature.
2. Verify that signature against Arch Linux ARM's published build-key fingerprint before touching it.
3. Assemble an MBR image on a native aarch64 Linux host with loop-device support.
4. Install pinned Omarchy sources and the ARM package set.
5. Remove factory credentials, blank machine identity and SSH host keys, then arm storage expansion and owner onboarding.
6. Remove build-only dependencies and PC-only firmware while retaining the Pi's Broadcom firmware and common Realtek USB-adapter support.
7. Parse the owner configuration with the image's ARM64 Hyprland binary and Pi profile, then audit the mounted result for Pi firmware, VC4/V3D configuration, armed first-boot services, erased factory identity, Quattro session files, required packages, and AArch64 executables.
8. Zero unused ext4 blocks, compress the image, and emit exact hashes, a provenance manifest, the audit report, and schema-compatible Raspberry Pi Imager metadata.
9. Boot-test the artifact, then verify graphics and input on a real Pi 4.

No mystery blobs will be generated by CI. Every release artifact should be traceable back to a workflow run and the exact source revisions used to build it.

## Development

Run the focused Pi tests on any Unix-like development machine:

```bash
test/shell.d/raspberry-pi-test.sh
```

Run the inherited Omarchy CLI and shell suites before merging broader changes:

```bash
./test/all
```

Real-hardware acceptance remains the final word for HDMI scan-out, V3D acceleration, audio, Bluetooth, Wi-Fi, suspend behavior, and thermal stability. Test reports should include the Pi revision, RAM size, boot medium, display mode, power supply, and output from `omarchy-debug`.

## Known gaps

- The public Imager catalog is pinned to the alpha release rather than listed in Raspberry Pi Imager's stock OS directory; launch Imager with the documented `--repo` URL.
- The stock ext4 image has no Snapper rollback or factory reset.
- A few x86-only or unavailable apps are omitted; the core Quattro experience does not depend on them.
- High-resolution video recording and heavy Electron multitasking can overwhelm a Pi 4.
- Hardware verification has not yet covered every Pi revision, DSI panel, HAT, or USB boot enclosure.

## Credits

Built on [Omarchy](https://github.com/omacom/omarchy) by DHH and its contributors, [Arch Linux ARM](https://archlinuxarm.org/), [Hyprland](https://hypr.land/), [Quickshell](https://quickshell.org/), and the enormous body of Raspberry Pi kernel and Mesa work that makes a modern Wayland desktop on this board possible.

Omarchy is MIT-licensed. This port keeps that license and upstream attribution.
