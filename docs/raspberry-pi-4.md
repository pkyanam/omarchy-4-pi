# Omarchy Quattro on Raspberry Pi 4 Model B

This port installs the Quattro desktop natively on a Raspberry Pi 4 Model B. It does not emulate x86_64 and it does not use the upstream Omarchy ISO, which is built around an x86 boot flow and package repository.

## What the port changes

- Uses the official Arch Linux ARM aarch64 Raspberry Pi 4 root filesystem and repositories.
- Uses the Arch Linux ARM builds of Hyprland, Quickshell, Chromium, PipeWire, SDDM, and most of the standard Omarchy package set.
- Builds `omarchy`, `omarchy-settings`, the Omarchy keyring, and the required Nerd Font locally from the upstream Omarchy PKGBUILDs.
- Removes Limine and its mkinitcpio integration from the locally built packages. The Pi continues to boot through its firmware and U-Boot setup.
- Enables full VC4 KMS, loads the VC4/V3D kernel modules, installs the Broadcom Vulkan driver, and enables Aquamarine's limited-GPU modifier workaround.
- Keeps future package refreshes on Arch Linux ARM. Selecting the upstream stable, RC, or edge package channel is intentionally disabled because those repositories do not publish aarch64 packages.
- Skips Snapper configuration on the default ext4 root filesystem. Omarchy updates still run, but without pre-update system snapshots.
- Uses `wf-recorder` when `gpu-screen-recorder` is unavailable.

## Hardware and storage

Designed for Raspberry Pi 4 Model B with **4GB+ RAM**, a 64-bit installation, a reliable 3 A power supply, and at least 32 GB of storage. A USB 3 SSD is recommended for development I/O. The 8GB model provides more room for browser and agent-driven builds; smaller-than-4GB boards are outside the supported target. This is a support requirement, not a `total_mem` firmware limit.

Connect Ethernet for the first installation when possible. Wi-Fi is managed by NetworkManager after Omarchy setup.

## 1. Install Arch Linux ARM aarch64

Follow the official [Arch Linux ARM Raspberry Pi 4 installation instructions](https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4) and select the `ArchLinuxARM-rpi-aarch64-latest.tar.gz` root filesystem. Those instructions partition and overwrite the selected SD card or drive, so verify the device name on the machine preparing the media before running their commands.

On first boot, initialize the Arch Linux ARM keyring as documented there. Then, as root, update the base system and create a regular sudo-capable user. The Omarchy installer deliberately refuses to run as root.

One conventional setup is:

```bash
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --needed git sudo base-devel
useradd -m -G wheel -s /bin/bash yourname
passwd yourname
EDITOR=nano visudo
```

In `visudo`, uncomment the `%wheel ALL=(ALL:ALL) ALL` line. Log out of the default account and log in as the new user before continuing.

## 2. Install the port

Clone this Raspberry Pi branch and run the installer:

```bash
git clone https://github.com/pkyanam/omarchy-4-pi.git ~/omarchy-rpi4
cd ~/omarchy-rpi4
./install-rpi4.sh
```

The complete install resolves every package in `install/omarchy-base.packages` against the live Arch Linux ARM repositories, then builds ARM-compatible Omarchy applications from the official `omarchy-pkgs` recipes. This can take hours on a Pi 4 because packages such as Herdr, LocalSend, and the Neovim bundle compile or prepare substantial dependency trees.

For the complete Quattro shell and system integration without the optional locally built applications, use:

```bash
./install-rpi4.sh --minimal
```

The minimal mode still installs the desktop, browser, file manager, terminal, development tools available from Arch Linux ARM, themes, menus, notifications, lock screen, and Omarchy command suite. Optional shortcuts whose applications were not built simply do nothing until those applications are installed.

Reboot after the installer finishes:

```bash
sudo reboot
```

SDDM should start the Omarchy Hyprland session automatically.

## Build a flashable image instead

The repository's image factory runs on a native aarch64 Linux host. It verifies the official Arch Linux ARM detached signature against build key `68B3537F39A313B3E574D06777193F152BDBE6A6`, creates the Pi partition layout, installs the port in a chroot, removes factory credentials, and emits Raspberry Pi Imager-ready metadata.

RC1 selects a complete September 3, 2026 package snapshot from the community archive `pkgmirror.sametimetomorrow.net` using `default/pacman/mirrorlist-rpi4-image`. The bootstrap synchronizes the base to that snapshot, including downgrades when a newer base requires them. Official Arch Linux ARM package signatures remain required. Post-install setup restores the live `mirrorlist-rpi4`, and the mounted-root audit checks that the shipped image uses normal live ARM mirrors. The manifest records the build-only snapshot URL. Ordinary non-image installs continue using live mirrors.

On Debian or Ubuntu ARM64:

```bash
sudo apt-get update
sudo apt-get install libarchive-tools dosfstools e2fsprogs gnupg parted rsync xz-utils zerofree
sudo image/build-rpi4-image.sh --minimal
```

The output directory contains:

- `*.img.xz` — the compressed flashable disk image
- `*.img.xz.sha256` — compressed-download integrity hash
- `*.manifest.json` — source and `omarchy-pkgs` commits, signed base image, verified offline ARM64 Node bundle, mode, build time, and every final package version
- `*.audit.txt` — enforced Pi boot, provisioning, desktop-payload, in-image Hyprland parser, package-architecture, and factory-identity checks
- `*.os-list.json` and `os-list.json` — Raspberry Pi Imager 2.x catalog metadata with hashes of both the compressed download and extracted image

The default sparse image is 12 GiB before compression and grows to fill the target device on first boot. Before compression, the factory removes build-only dependencies and PC-only firmware, retains the Pi's Broadcom firmware plus common Realtek USB-adapter support, and zeroes unused ext4 blocks. It also stores only a shallow, upstream-tracking source checkout so updates still work without shipping hundreds of megabytes of unrelated history. A checksum-verified official Linux ARM64 Node.js bundle is staged so owner finalization remains offline-capable, matching the official Omarchy ISO flow without carrying its x86_64 archive. Override the image-size floor with `OMARCHY_IMAGE_SIZE_GIB`; values below 12 GiB are rejected because the complete desktop's transient installation footprint does not fit safely even though the finished payload is smaller. The first boot has no reusable `alarm` or root password: it expands storage, then Omarchy's owner-provisioning UI asks for keyboard, username, password, identity, hostname, and timezone before starting SDDM. Pi-only systemd dependencies make owner creation wait for a successful root expansion and SDDM wait for successful owner creation; a failed grow keeps both one-shot markers armed so the operation can retry safely on the next boot instead of exposing a user-less login screen.

### Raspberry Pi Imager 2.x customization

Catalog metadata generated from current `main` declares the official `rpi-preseed` customization format. Raspberry Pi Imager 2.x then writes `rpi-preseed.toml` to the FAT boot partition, where Omarchy's first-boot service consumes the Imager-generated subset:

- owner username and pre-hashed password
- hostname, keyboard map, and timezone
- NetworkManager Wi-Fi profile and regulatory country
- optional SSH with password authentication or validated public keys
- optional passwordless sudo when explicitly selected

Omarchy refuses a plaintext owner password from the FAT partition, requires a complete username/password pair before bypassing the interactive form, and falls back to the normal HDMI setup if the file is missing, partial, malformed, or unsafe. Encrypted/LUKS installs also retain interactive setup because an Imager password hash cannot re-key a LUKS volume. The boot-partition source and transient staging state are removed after successful provisioning; required credentials remain only in protected system stores, and a non-secret receipt remains in `/var/lib/omarchy/imager-preseed.json` for diagnostics.

Enter a short hostname such as `omarchy-pi` in Imager, without `.local`. Starting with RC1, owner setup applies and verifies the static and transient hostnames before configuring SSH; Avahi waits until owner provisioning finishes before advertising the device. A failed hostname assignment stops that unattended attempt instead of silently continuing with the factory name. A Mac on the same network can normally connect using `ssh USER@omarchy-pi.local`. Networks that filter multicast discovery may require the address shown in the router's client list instead. The receipt in `/var/lib/omarchy/imager-preseed.json` records the requested hostname without credentials; compare it with `hostnamectl --static` when troubleshooting.

Raspberry Pi Imager 2.x deliberately treats a locally selected **Use custom** image as `init_format: none`, because the file itself does not carry catalog metadata. Unattended customization becomes available when selecting the image through its generated catalog or a local manifest. On macOS, generate and open the latter in one step:

```bash
image/open-in-rpi-imager-macos.sh build/image/omarchy-4-pi-*.img.xz
```

The helper verifies the compressed and extracted image hashes, writes a path-safe `.imager.json` beside the image, checks for Raspberry Pi Imager 2.0.11 or newer, and opens a loopback-only catalog. Imager 2.0.10 and older reject `rpi-preseed` as an unknown customization format and prune the entry, so they cannot provide this workflow. Keep the helper's terminal open until Imager finishes: its temporary HTTP server binds to `127.0.0.1`, never the LAN, and stops when Imager closes. Select **Omarchy 4 Pi** in the app rather than **Use custom**, then complete Imager's customization wizard before writing. On another OS with a compatible Imager, run `image/generate-local-imager-manifest.sh IMAGE.img.xz` and load the resulting manifest through Imager's custom content repository control. This follows Raspberry Pi's [current customization-format contract](https://github.com/raspberrypi/rpi-imager/blob/main/doc/os_customisation_formats.md), without importing Raspberry Pi OS-specific `firstrun.sh` behavior into Arch Linux ARM.

The same builder runs in `.github/workflows/build-rpi4-image.yml` on GitHub's native `ubuntu-24.04-arm` runner. Manual builds are retained as workflow artifacts. Version tags publish the image directly when it fits GitHub's per-file limit; larger images are released as numbered, independently checksummed parts with exact reassembly instructions.

## Verification

### Display recovery

Run `omarchy-pi-display` as your desktop user to see detected modes, scaling, configuration errors, and HDMI EDID byte counts. Scaling changes desktop density, not the physical video mode. Empty EDID and only low-resolution fallback modes indicate missing monitor capability data; they do not establish which cable, adapter, monitor, or driver caused the problem.

For the NEC MultiSync EA243WM only, `omarchy-pi-display nec-ea243wm HDMI-A-1` previews the native 1920×1200, 60 Hz reduced-blanking timing at scale 1. It requires an interactive terminal, checks that Hyprland accepted the mode, and asks for `yes` within 30 seconds. No confirmation means it attempts to restore the previous mode without saving. Confirmation writes a private Lua profile under `$XDG_STATE_HOME/omarchy/toggles/hypr` (normally `~/.local/state/omarchy/toggles/hypr`), which the desktop loads after user monitor settings. This also works over SSH when exactly one desktop session is running.

Disable the override with `omarchy-pi-display reset HDMI-A-1`; the profile is renamed to a backup and Hyprland reloads normal settings. This does not guarantee HDMI audio when EDID remains unreadable. Do not apply that model-specific profile to an unrelated display. Other monitors retain their normal preferred-mode detection.

### System checks

After logging in, check the architecture, renderer, session, and shell:

```bash
omarchy-pi-check
```

It prints a paste-friendly PASS/WARN/FAIL report and exits nonzero when a
required hardware checkpoint fails. It does not print SSIDs, IP addresses,
Bluetooth addresses, passwords, or keys. For deeper inspection, run:

```bash
uname -m
omarchy-pi-status
glxinfo -B | sed -n '/Device:/p;/OpenGL renderer/p'
hyprctl version
hyprctl monitors
omarchy-shell shell ping
omarchy version channel
wpctl status
bluetoothctl show
```

Expected results are `aarch64`, a V3D/VC4 Mesa renderer rather than `llvmpipe`, a detected HDMI output, a successful shell ping, the `rpi4` channel, PipeWire audio devices, and a Pi Bluetooth controller. `omarchy-pi-status` summarizes temperature, memory, storage, renderer, and Raspberry Pi firmware power flags. `OK` means no under-voltage or throttling was recorded since boot; an `ACTIVE` warning should be fixed before diagnosing desktop performance, while `previously` identifies a transient event that has cleared.

If `glxinfo` is missing, install `mesa-utils` with `sudo pacman -S mesa-utils`.

## Updates

Run normal system and AUR updates through Omarchy:

```bash
omarchy update
```

The installer records its source checkout in `/etc/omarchy-rpi4.conf`. Current source validates that its origin is `pkyanam/omarchy-4-pi` and it tracks `origin/main`; unexpected origins, branches, dirty checkouts, and package repositories stop the update before installation. It fast-forwards that checkout, reconciles minimal runtime dependencies, and rebuilds the four ported core packages before continuing with Arch Linux ARM packages and migrations. A success marker is written only after package installation, so failed rebuilds remain retryable. Local changes are never overwritten. The first downloadable image predates these additional safeguards; see the [audit and rollout notes](pi-performance.md#update-path-audit).

Commands that normally refresh Limine detect this profile and leave the Pi firmware boot partition alone. Plymouth refreshes still rebuild the Arch Linux ARM initramfs directly with `mkinitcpio`, so `omarchy-reinstall-configs` works on the Pi instead of failing on a PC-only bootloader step.

Do not delete or move the source checkout without updating `OMARCHY_RPI4_SOURCE` in `/etc/omarchy-rpi4.conf`.

The stable, RC, edge, and dev channel switcher is disabled on this port. `omarchy refresh pacman` always restores the Raspberry Pi package profile.

## Known limitations

- The upstream Omarchy ISO cannot boot the Pi and the upstream Omarchy package mirrors do not currently serve aarch64. Installation therefore starts from Arch Linux ARM and builds the Omarchy core locally.
- The default ext4 layout has no Snapper system snapshots or factory reset. Btrfs is not required for the desktop to run, but updates are less recoverable than on the x86 Omarchy ISO.
- Obsidian, Pinta, the Hyprland preview share picker, Tensaku, and `dotnet-runtime` are omitted because the current recipes or upstream binaries do not support this aarch64 target. `asdcontrol` is Apple-specific. The QEMU static-user package is omitted to keep installation practical on Pi hardware.
- Screen recording uses CPU encoding through `wf-recorder`; 1080p at 30 fps is the realistic target. High-resolution recording competes with the compositor and browser for the Pi's CPU and memory bandwidth.
- Full desktop verification still requires real Pi hardware. The repository tests cover detection, boot configuration, package profiles, script parsing, and non-Btrfs behavior, but they cannot prove HDMI scan-out or V3D rendering from a non-Pi CI host.

## Recovery

If SDDM reaches a black screen, switch to a text console with `Ctrl+Alt+F3` or connect over SSH and inspect:

```bash
journalctl -b -u sddm --no-pager
journalctl --user -b -u wayland-wm@Hyprland.service --no-pager
ls -l /dev/dri
grep -E 'dtoverlay=vc4-kms-v3d|max_framebuffers|disable_fw_kms_setup' /boot/config.txt
```

The expected DRM nodes are a KMS card device and a V3D render node. The installer writes `dtoverlay=vc4-kms-v3d`, `max_framebuffers=2`, and `disable_fw_kms_setup=1` to the detected Pi boot configuration. If a specialized DSI display requires its own overlay, follow the display vendor's KMS instructions and keep the full VC4 KMS overlay enabled.
