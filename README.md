<div align="center">
  <img src="docs/assets/hero-placeholder.svg" alt="Omarchy 4 Pi — Quattro on Raspberry Pi 4" width="100%">

  # Omarchy 4 Pi

  **The delightfully opinionated Omarchy Quattro desktop, remixed for Raspberry Pi 4.**

  [![Project status: alpha](https://img.shields.io/badge/status-alpha-f5a97f?style=for-the-badge)](#project-status)
  [![Target: Raspberry Pi 4](https://img.shields.io/badge/target-Raspberry_Pi_4-c51a4a?style=for-the-badge&logo=raspberrypi&logoColor=white)](#what-you-need)
  [![Architecture: ARM64](https://img.shields.io/badge/architecture-ARM64-1793d1?style=for-the-badge&logo=archlinux&logoColor=white)](#how-it-works)
  [![License: MIT](https://img.shields.io/badge/license-MIT-a6da95?style=for-the-badge)](LICENSE)

  *Tiny board. Big desktop energy.*
</div>

> [!IMPORTANT]
> This is an independent community port and is not an official Omarchy or Raspberry Pi product. The image builder is under active development; the current in-place installer is ready for controlled testing on Arch Linux ARM, but real-hardware desktop verification is still in progress.

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
| Reproducible `.img` builder | 🚧 | Next milestone |
| First prebuilt image release | ⏳ | Follows image-builder and boot verification |
| Raspberry Pi Imager catalog entry | ⏳ | Requires stable hosted release artifacts |

Legend: ✅ implemented and locally verified · 🧪 ready for hardware testing · 🚧 being built · ⏳ queued

## What you need

- Raspberry Pi 4 Model B — the 8 GB model is nicest, 4 GB is supported as a target
- 32 GB or larger microSD card; a USB 3 SSD is strongly recommended
- The official-quality 5 V / 3 A power supply
- HDMI display, keyboard, and network access for first boot
- A taste for tiling windows on improbably small computers

## Try it today

Until the flashable image lands, start with the official [Arch Linux ARM aarch64 Raspberry Pi 4 root filesystem](https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4), create a regular sudo-capable user, then run:

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

The image builder will be boring in the best way:

1. Download a pinned Arch Linux ARM Raspberry Pi 4 root filesystem.
2. Verify its published checksum before touching it.
3. Assemble the image in a container or Linux host with loop-device support.
4. Install pinned Omarchy sources and the ARM package set.
5. Add a first-boot service for machine-specific expansion and onboarding.
6. Boot-test the artifact under aarch64 emulation, then verify graphics and input on a real Pi 4.
7. Compress the image reproducibly and emit checksums plus a software manifest.

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

- No downloadable `.img` exists yet. That is the active milestone, not a euphemism.
- The stock ext4 image has no Snapper rollback or factory reset.
- A few x86-only or unavailable apps are omitted; the core Quattro experience does not depend on them.
- High-resolution video recording and heavy Electron multitasking can overwhelm a Pi 4.
- Hardware verification has not yet covered every Pi revision, DSI panel, HAT, or USB boot enclosure.

## Credits

Built on [Omarchy](https://github.com/omacom/omarchy) by DHH and its contributors, [Arch Linux ARM](https://archlinuxarm.org/), [Hyprland](https://hypr.land/), [Quickshell](https://quickshell.org/), and the enormous body of Raspberry Pi kernel and Mesa work that makes a modern Wayland desktop on this board possible.

Omarchy is MIT-licensed. This port keeps that license and upstream attribution.
