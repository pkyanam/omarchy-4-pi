<p align="center">
  <img src="docs/assets/hero.png" alt="Omarchy mark × Raspberry Pi logo" width="100%">
</p>

# Omarchy 4 Pi · 4.5

**Omarchy 4.5 for Raspberry Pi 4 Model B, with 4GB or 8GB RAM.** A complete Hyprland and Quickshell desktop, tuned for the Pi, with Codex and the built-in Omarchy skills ready to help you configure, understand, and repair your system.

[**Download 4.5**](https://github.com/pkyanam/omarchy-4-pi/releases/latest) · [Release notes](docs/releases/v4.5.0.md) · [Installation guide](docs/raspberry-pi-4.md) · [Report a problem](https://github.com/pkyanam/omarchy-4-pi/issues/new?template=bug.yml)

[![Pi port checks](https://github.com/pkyanam/omarchy-4-pi/actions/workflows/pi-checks.yml/badge.svg)](https://github.com/pkyanam/omarchy-4-pi/actions/workflows/pi-checks.yml) [![Release](https://img.shields.io/github/v/release/pkyanam/omarchy-4-pi)](https://github.com/pkyanam/omarchy-4-pi/releases/latest) [![MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## Start here

1. Get a **Pi 4 Model B with 4GB or 8GB RAM**, reliable power, a display, keyboard and mouse, and a **32GB or larger microSD card or USB SSD**.
2. Open the [4.5 release](https://github.com/pkyanam/omarchy-4-pi/releases/latest), follow its Imager instructions, and write the image to spare media. Flashing erases the selected drive.
3. Set your username, password, hostname, network, and optional SSH access in **Raspberry Pi Imager 2.0.11 or newer**. Boot and let first-boot setup finish.
4. Open a terminal and run `omarchy-pi-check`. Then set up Codex below.

**Already using an older Pi image?** Move to 4.5 on spare media and keep your working card. The package repositories changed; an in-place 4.0-to-4.5 upgrade is not supported. [Migration and recovery](docs/pi-upgrade.md).

## Let Codex help

Omarchy includes agent integration and a substantial [Omarchy OS skill](default/agents/skills/omarchy/SKILL.md). First-user setup makes it available to Codex automatically, including a [Pi-specific guide](default/agents/skills/omarchy/raspberry-pi.md). The model runs through your provider; the Pi does not need to run a local language model.

Choose Codex from the Omarchy menu under **Setup → Default → Agent**, or run:

```bash
omarchy default agent codex
```

This installs Codex when needed and launches it. Connect to the internet and sign in when prompted. On subsequent visits, open your default agent with:

```bash
omarchy agent
```

Give it a concrete problem. For example:

```text
Use the Omarchy skill and its Raspberry Pi guide. This is Omarchy 4 Pi 4.5
on a Raspberry Pi 4. Run omarchy-pi-check and omarchy pi report --json,
then investigate why [describe the problem]. Read the relevant logs,
explain the cause, and make the smallest reversible fix. Keep my display,
font, and theme choices. Verify the result and tell me what changed.
```

The skill covers desktop settings, Hyprland, themes, plugins, services, and troubleshooting. Ask for user configuration changes in `~/.config/`; package-owned files under `/usr/share/omarchy/` are replaced by updates. A source-code fix belongs in a checkout of this repository following [AGENTS.md](AGENTS.md). Keep the Pi boot chain and `stable-4.5` repositories intact, and never bypass the update guard to force an old card through the transition.

For a build-heavy agent session, especially on 4GB:

```bash
omarchy pi run --plan -- codex   # Show the resource budget
omarchy pi run -- codex          # Run Codex in a bounded workload scope
```

This leaves room for the desktop. It limits resources; it is not a security sandbox. Save your work before long builds. Review logs before sharing them and leave passwords, private keys, and provisioning secrets out of reports.

## Flash with Raspberry Pi Imager

The [4.5 release](https://github.com/pkyanam/omarchy-4-pi/releases/tag/v4.5.0) contains numbered image parts because the compressed image exceeds GitHub's per-file limit. Download every `.img.xz.part-*` file, the `.parts.sha256` and `.sha256` files, and the `REASSEMBLE.txt` instructions. Verify the parts, join them, and verify the complete image as instructed.

Then use the local helper below to open the complete image in Imager with customization enabled. This release has no remote whole-image catalog. Choose the **Raspberry Pi 4** device and **Omarchy 4 Pi** entry, then configure your account and network before writing. Use a short hostname such as `omarchy-pi`, without `.local`. SSH is opt-in; there is no reusable factory login.

### Already downloaded the image?

Verify its `.sha256` file from the download directory:

```bash
# macOS
shasum -a 256 -c omarchy-4-pi-*.img.xz.sha256
# Linux
sha256sum -c omarchy-4-pi-*.img.xz.sha256
```

Clone this repository and give the macOS helper the exact image path:

```bash
git clone https://github.com/pkyanam/omarchy-4-pi.git
cd omarchy-4-pi
image/open-in-rpi-imager-macos.sh "/path/to/omarchy-4-pi-RELEASE-minimal.img.xz"
```

It verifies the image, serves a local catalog on `127.0.0.1`, and opens Imager with customization enabled. Keep the terminal open until flashing finishes. On Linux, use `image/generate-local-imager-manifest.sh IMAGE.img.xz` and open the generated catalog with `rpi-imager --repo`.

Choosing **Use custom** directly in Imager omits the catalog's customization metadata. That path uses the on-screen **Press Return to Start Setup** flow and needs a keyboard. The catalog route supports account and network setup before the first boot.

## After the first boot

Let storage expansion and owner setup finish. Then check:

```bash
omarchy-pi-check
omarchy pi report --json
omarchy-pi-display
hostnamectl --static
```

If SSH was enabled, connect from another computer on the same network:

```bash
ssh YOUR_USERNAME@omarchy-pi.local
```

If `.local` does not resolve, use the address shown by your router. Guest networks and client isolation can block discovery. Check actual audio playback and Bluetooth pairing as well as service status.

For display problems, start with [display recovery](docs/raspberry-pi-4.md#display-recovery). The reversible `omarchy-pi-display nec-ea243wm HDMI-A-1` profile exists for the historically tested NEC EA243WM setup with missing EDID; other displays use their detected preferred modes. Scaling does not fix missing display timings.

## What 4.5 includes

| Area | Included |
| --- | --- |
| Desktop | Native ARM64 Hyprland, Quickshell panels, floating workspaces and dock, launcher, notifications, themes and locking |
| Everyday tools | Chromium, terminal, file manager, editor and the applications required by 4.5 |
| Agents | Default-agent selection, Codex support, Omarchy skills and Pi resource helpers; agent downloads and authentication need a connection |
| Typography | Self-hosted Paper Mono with its SIL Open Font License and monospace fallbacks |
| Graphics | VC4 KMS, V3D Mesa and Broadcom Vulkan packages, with the Pi configuration retained |
| First boot | Root expansion, Imager customization, owner setup, hostname and opt-in SSH provisioning |
| Resource policy | Stock clocks, reduced motion, static backgrounds, half-RAM compressed swap, bounded logging and package/build concurrency |
| Maintenance | Pi-aware updates, signed ARM packages, source/package receipts and retryable failure handling |

The image uses Arch Linux ARM, the Pi firmware/U-Boot boot path and plain ext4. “Minimal” omits optional heavyweight applications while keeping the complete desktop. Disk encryption, Limine and automatic Snapper rollback are not part of this image.

The preceding 4.5 candidate **boots and runs on the maintainer's Pi**, as reported on November 7, 2026. The published 4.5 image passed 192 assembled-image checks, native ARM64 Hyprland configuration parsing, dependency and service-unit checks, filesystem checks, the production update guard, offline Node/npm execution and actual ARM64 Codex installation/launcher execution. Detailed performance, media decoding, peripherals and separate 4GB/8GB qualification remain open. **Pi 5 is deferred.** See the [validation ledger](plans/omarchy-4.5-pi4.md).

## Updates and recovery

On the published 4.5 image, back up important files and run:

```bash
omarchy update
```

Core updates follow **this repository's `main` branch**, with a clean checkout tracking `origin/main`. The updater verifies the Pi's `stable-4.5` repository policy, maintains the adapted core/settings packages, and stops visibly on failures. Personal display, font and theme choices are preserved. This is a moving `main` update path, not a release-tag selector.

Earlier rolling images need a [fresh-media transition](docs/pi-upgrade.md). Development candidate images retain their actual branch and intentionally fail the production update guard. Do not rename branches or change repository markers to bypass it. Back up the whole card for recovery: a Git reset cannot undo installed packages or boot files, and this ext4 image has no automatic pre-update snapshot.

For performance tuning and recovery, see [Pi tuning](docs/pi-tuning.md). Stock clocks and thermal protection remain the default; Raspberry Pi OS performance parity is a measurement target, not an achieved claim.

## Build your own image

On an Apple-silicon Mac with Docker Desktop or OrbStack running, from a clean checkout of `main` matching `origin/main`:

```bash
image/build-rpi4-image-macos.sh --minimal
```

The builder uses native ARM64, bounded workers and memory, and a private disk-backed workspace. It does not change global VM settings. Artifacts land in `build/image/`. For a smaller download at the cost of a longer build:

```bash
OMARCHY_XZ_PRESET=-9e OMARCHY_XZ_MEMORY_MIB=768 \
  image/build-rpi4-image-macos.sh --minimal
```

On an ARM64 Debian/Ubuntu host with loop-device support:

```bash
sudo apt-get update
sudo apt-get install libarchive-tools dosfstools e2fsprogs gnupg parted python3 rsync xz-utils zerofree
sudo image/build-rpi4-image.sh --minimal
```

GitHub's **Build Raspberry Pi image** workflow provides the same native ARM64 factory. Use `--full` to request additional optional applications available from the signed repositories. Unpublished or modified source is identified as a candidate.

The factory verifies the signed base filesystem, assembles a coherent stable package set, removes factory accounts and machine identity, validates the packaged Hyprland configuration, and audits the finished filesystem. Every image records source and recipe commits, exact package versions, repository URLs and the verified offline Node bundle. These records provide traceability; mutable repositories prevent a bit-for-bit reproducibility promise.

See [installation and build details](docs/raspberry-pi-4.md) for direct fresh ALARM installation and [the 4.5 design guide](docs/omarchy-4.5-pi4.md) for architecture and validation boundaries.

## Contribute or report a problem

Use [Issues](https://github.com/pkyanam/omarchy-4-pi/issues/new?template=bug.yml) for reproducible problems and [Discussions](https://github.com/pkyanam/omarchy-4-pi/discussions) for questions. Include the release or commit, board revision and RAM, power supply, storage, display connection, reproduction steps and reviewed diagnostic output. Do not upload the raw Imager preseed file or network credentials. Report vulnerabilities through [private reporting](.github/SECURITY.md).

Agents contributing code should read [AGENTS.md](AGENTS.md), the matching guide in [agents/skills/](agents/skills/), and [docs/testing.md](docs/testing.md). Run focused tests for the changed area and preserve their full output, for example:

```bash
bash test/shell.d/rpi-update-safety-test.sh >/tmp/rpi-update-safety.log 2>&1
cat /tmp/rpi-update-safety.log
```

Graphical acceptance runs in a disposable VM. Physical HDMI, audio, input, Wi-Fi, Bluetooth, power and thermal checks require real boards. A container pass does not replace those checks.

## Credits and license

An independent community port of [Omarchy](https://omarchy.org/) by DHH and contributors, built with [Arch Linux ARM](https://archlinuxarm.org/), [Hyprland](https://hypr.land/), [Quickshell](https://quickshell.org/) and the Raspberry Pi firmware, kernel and Mesa ecosystem. It is not an official Omarchy or Raspberry Pi product.

Code is [MIT licensed](LICENSE), with upstream attribution and separately licensed bundled assets retained. The generated header depicts the Omarchy and Raspberry Pi marks; those marks belong to their respective owners. [Artwork provenance](docs/assets/hero-art-direction.md).
