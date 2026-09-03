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

Use a Raspberry Pi 4 Model B with a 64-bit-capable installation, a reliable 3 A power supply, and at least 32 GB of storage. A USB 3 SSD is strongly recommended; a full install builds several packages and writes much more data than a small desktop image. The 8 GB model provides the most comfortable build and browser experience, but the port does not hard-code a memory size.

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

On Debian or Ubuntu ARM64:

```bash
sudo apt-get update
sudo apt-get install libarchive-tools dosfstools e2fsprogs gnupg parted rsync xz-utils
sudo image/build-rpi4-image.sh --minimal
```

The output directory contains:

- `*.img.xz` — the compressed flashable disk image
- `*.img.xz.sha256` — compressed-download integrity hash
- `*.manifest.json` — source commit, base image, signing key, mode, and build time
- `*.os-list.json` and `os-list.json` — Raspberry Pi Imager 2.x catalog metadata with hashes of both the compressed download and extracted image

The default sparse image is 12 GiB before compression and grows to fill the target device on first boot. Override that floor with `OMARCHY_IMAGE_SIZE_GIB`, but values below 10 GiB are rejected. The first boot has no reusable `alarm` or root password: it expands storage, then Omarchy's owner-provisioning UI asks for keyboard, username, password, identity, hostname, and timezone before starting SDDM.

The same builder runs in `.github/workflows/build-rpi4-image.yml` on GitHub's native `ubuntu-24.04-arm` runner. Manual builds are retained as workflow artifacts. Version tags publish the image directly when it fits GitHub's per-file limit; larger images are released as numbered, independently checksummed parts with exact reassembly instructions.

## Verification

After logging in, check the architecture, renderer, session, and shell:

```bash
uname -m
glxinfo -B | sed -n '/Device:/p;/OpenGL renderer/p'
hyprctl version
hyprctl monitors
omarchy-shell shell ping
omarchy version channel
```

Expected results are `aarch64`, a V3D/VC4 Mesa renderer rather than `llvmpipe`, a detected HDMI output, a successful shell ping, and the `rpi4` channel.

If `glxinfo` is missing, install `mesa-utils` with `sudo pacman -S mesa-utils`.

## Updates

Run normal system and AUR updates through Omarchy:

```bash
omarchy update
```

The installer records its source checkout in `/etc/omarchy-rpi4.conf`. During an update, Omarchy fast-forwards that checkout and locally rebuilds the four ported Omarchy packages before continuing with the Arch Linux ARM package and migration steps. Local changes in the checkout cause the core rebuild to be skipped rather than overwritten.

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
