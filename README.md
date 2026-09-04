<div align="center">
  <img src="docs/assets/hero-placeholder.svg" alt="Omarchy 4 Pi — Quattro on Raspberry Pi 4" width="100%">

  # Omarchy 4 Pi

  **Tiny board. Big desktop energy.**

  The opinionated Omarchy Quattro desktop, remixed for Raspberry Pi 4.

  [![Pi port checks](https://github.com/pkyanam/omarchy-4-pi/actions/workflows/pi-checks.yml/badge.svg)](https://github.com/pkyanam/omarchy-4-pi/actions/workflows/pi-checks.yml)
  [![Releases](https://img.shields.io/github/v/release/pkyanam/omarchy-4-pi?include_prereleases)](https://github.com/pkyanam/omarchy-4-pi/releases)
  [![MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
</div>

Hyprland tiling. Quickshell panels. Omarchy themes, launcher, terminal tools, Chromium, and a surprisingly grown-up desktop on a very small computer.

> [!IMPORTANT]
> Independent community port—not an official Omarchy or Raspberry Pi product. **RC1 is our first release candidate, not a stable release.** The tester reports RC1 working on their Pi 4. RC1 adds hostname sequencing and display recovery; the detailed hardware acceptance checklist remains open. See [release notes](docs/releases/v0.1.0-rc.1.md) and the [hardware checklist](https://github.com/pkyanam/omarchy-4-pi/issues/1).

## Flash, boot, make it yours

You need a **Raspberry Pi 4 Model B**, a reliable power supply, HDMI display, and a **32 GB or larger** microSD card or USB SSD. Back up the target drive: flashing erases it. An SSD and 4–8 GB RAM provide more breathing room. Pi 5, Pi 400, and other boards are not validated targets.

Install Raspberry Pi Imager **2.0.11 or newer**. On macOS, open the RC1 catalog:

```bash
open -n -a "/Applications/Raspberry Pi Imager.app" --args --repo \
  "https://github.com/pkyanam/omarchy-4-pi/releases/download/v0.1.0-rc.1/os-list.json"
```

The [RC1 release](https://github.com/pkyanam/omarchy-4-pi/releases/tag/v0.1.0-rc.1) contains the verified image and `os-list.json`. The 2.08 GB download passed checksum/catalog verification and an independent read-only audit of 111 image invariants. The tester reported it working on their Pi 4 on September 4, 2026; this initial success does not establish that every hardware acceptance check has passed.

1. Select the **Raspberry Pi 4** device and **Omarchy 4 Pi** OS entry.
2. Select your SD card or SSD. Double-check which drive will be erased.
3. Set your **username, password, hostname, timezone, and keyboard**. Configure Wi-Fi if needed; explicitly enable SSH if you want remote access.
4. Write and verify. Boot the Pi and let first-boot storage expansion and owner setup finish.

**Use a short hostname such as `omarchy-pi`, without `.local`.** RC1 applies and verifies that name before starting the configured SSH service, and delays Avahi/mDNS advertising until owner provisioning finishes. It does not replace your chosen name with `omarchy`.

From a Mac on the same network:

```bash
ssh YOUR_USERNAME@omarchy-pi.local
```

Complete Imager account settings allow keyboard-free provisioning. The desktop itself is best used with a keyboard and mouse. The factory image has **no reusable default login**, and SSH is opt-in.

> [!TIP]
> Choose the OS through this catalog, **not “Use custom”**, if you want Imager customization. A bare downloaded image does not expose that metadata: “Use custom” leads to the on-screen **Press Return to Start Setup** flow and needs a keyboard.

### Already downloaded the image?

Clone this repository, then run its macOS helper with one exact image path:

```bash
image/open-in-rpi-imager-macos.sh "/path/to/omarchy-4-pi-RELEASE-minimal.img.xz"
```

It verifies the image, serves a catalog only to `127.0.0.1`, and opens Imager with customization enabled. Keep the terminal open until flashing finishes. Closing Imager stops the local server.

If the device picker is blank, quit the old Imager window, check the installed version, and reopen with the RC1 catalog above. The catalog includes the device metadata required by Imager 2.x.

## First lap around the desktop

Run these in the Pi's terminal or over SSH:

```bash
omarchy-pi-check
omarchy-pi-display
hostnamectl --static
```

The health check covers provisioning, graphics, desktop services, networking, audio readiness, Bluetooth readiness, and power/temperature sensors. A running service is **not** proof that speakers play or a Bluetooth peripheral pairs—please test those too.

### NEC EA243WM stuck at 1024×768?

One tested HDMI adapter/cable/monitor setup returned **zero EDID bytes**, so Linux could not discover the NEC's native 1920×1200 mode. Scaling alone cannot fix missing display timings.

RC1 includes an opt-in profile using the native timing that the tester reported working:

```bash
omarchy-pi-display nec-ea243wm HDMI-A-1
```

Run interactively as your desktop user (SSH works). It previews **1920×1200 at 60 Hz, scale 1**; type `yes` within 30 seconds only if the picture looks right. Otherwise it attempts to restore the previous mode. A confirmed profile survives login and reboot. To disable it, retaining a backup:

```bash
omarchy-pi-display reset HDMI-A-1
```

This profile is specific to that NEC model. Other monitors keep normal preferred-mode detection. A timing override does not repair EDID or guarantee HDMI audio. See [display troubleshooting](docs/raspberry-pi-4.md#display-recovery).

## What's in the box?

| Included | Deliberately different |
| --- | --- |
| Native ARM64 Hyprland + Quickshell | Arch Linux ARM packages, not x86 emulation |
| VC4 KMS, V3D Mesa, Broadcom Vulkan | Pi firmware + U-Boot; no Limine |
| Chromium, terminal, file manager, themes, core tools | Optional heavyweight/unavailable apps omitted from the minimal image |
| PipeWire, Bluetooth services, NetworkManager | Hardware playback/pairing still needs broader testing |
| Automatic root expansion and Imager owner setup | Plain ext4; no disk encryption or Snapper rollback |
| Pi-aware updates and diagnostics | Upstream x86 package-channel switching is blocked |

“Minimal” means fewer optional applications, **not half a desktop**.

## Build your own image

### Apple-silicon Mac

With Docker Desktop running:

```bash
git clone https://github.com/pkyanam/omarchy-4-pi.git
cd omarchy-4-pi
image/build-rpi4-image-macos.sh --minimal
```

The builder uses native ARM64, leaves two logical CPU cores free by default, keeps heavy I/O inside Docker, and uses fast xz compression. Artifacts land in `build/image/`. Override `OMARCHY_LOCAL_CPUS` to set a smaller budget, or `OMARCHY_XZ_PRESET=-6` for a smaller, slower download.

### ARM64 Linux or GitHub Actions

On an ARM64 Ubuntu/Debian host with loop-device support:

```bash
sudo apt-get update
sudo apt-get install libarchive-tools dosfstools e2fsprogs gnupg parted rsync xz-utils zerofree
sudo image/build-rpi4-image.sh --minimal
```

Or choose **Actions → Build Raspberry Pi image → Run workflow**. Version tags publish release assets; manual runs retain workflow artifacts. `--full` also builds optional ARM-compatible applications and takes considerably longer.

Each build provides a compressed `.img.xz`, SHA-256 checksum, Imager catalog, package/source manifest, and mounted-root audit report. The image expands from its 12 GiB factory size on first boot. The factory verifies the signed Arch Linux ARM base, removes default accounts and machine identity, checks the actual ARM64 Hyprland configuration, and audits the assembled root filesystem before publishing.

RC1 factory builds use the **September 3, 2026 package snapshot** from a community Arch Linux ARM archive, with official package signatures still required. This avoids a later upstream Aquamarine/Hyprland library mismatch. Normal live ARM mirrors are restored before shipping, so updates are not permanently frozen. The archive URL, resolved packages, and source commits are recorded in each manifest. Builds are **traceable, not bit-for-bit reproducible**: the signed base filesystem and some build inputs still roll forward.

For existing Arch Linux ARM installs and deeper build details, see the [installation guide](docs/raspberry-pi-4.md).

## Updates and recovery

Use `omarchy update` for the Pi-aware update path. Back up important files first: this ext4 image has no automatic pre-update snapshot. Reflashing erases the card; testing RC1 on a spare card preserves your existing install. A source update alone does not replay first-boot setup or prove RC1's new image behavior.

If `HOSTNAME.local` does not resolve, try the Pi's IP address from your router. Multicast discovery can be blocked by guest networks or client isolation. Compare `hostnamectl --static` with the non-secret provisioning receipt:

```bash
sudo jq '{hostname}' /var/lib/omarchy/imager-preseed.json
```

The generic ARM64 kernel may not expose `/dev/vcio_gencmd`; that does not by itself mean power is bad. Pi diagnostics use Linux's native voltage and thermal sensors when the legacy tool is unavailable.

## Testing and contributing

Reports from real boards are welcome. Start with [a Pi bug report](https://github.com/pkyanam/omarchy-4-pi/issues/new?template=bug.yml) or [Discussions](https://github.com/pkyanam/omarchy-4-pi/discussions). Include the release/commit, Pi revision and RAM, power supply, storage, display connection, reproduction steps, and `omarchy-pi-check` output. Review logs before posting; **never upload Wi-Fi passwords, keys, or the raw preseed file**.

Focused tests:

```bash
test/shell.d/raspberry-pi-test.sh
test/shell.d/rpi-imager-preseed-test.sh
test/shell.d/rpi-owner-hostname-test.sh
test/shell.d/rpi-display-test.sh
test/shell.d/rpi-grow-root-test.sh
test/shell.d/rpi-hyprland-verify-test.sh
```

Broader Omarchy changes also need the inherited `./test/all` suite on Linux. Graphical acceptance runs in a disposable VM; final HDMI, audio, input, Wi-Fi, Bluetooth, and thermal acceptance requires real hardware. Contributor procedures are in [AGENTS.md](AGENTS.md); suspected vulnerabilities go through [private reporting](.github/SECURITY.md).

Known limits: missing-EDID displays need troubleshooting; high-resolution capture and heavy multitasking can outpace a Pi 4; DSI panels, HATs, boot enclosures, and every board revision have not been validated. RC1 is an invitation to test, not a promise that every peripheral works.

## Credits

Built on [Omarchy](https://github.com/omacom/omarchy) by DHH and contributors, [Arch Linux ARM](https://archlinuxarm.org/), [Hyprland](https://hypr.land/), [Quickshell](https://quickshell.org/), and Raspberry Pi's kernel, firmware, and Mesa ecosystem.

MIT-licensed; upstream attribution is retained. The header artwork is a placeholder—real Pi desktop glamour shots are welcome.
