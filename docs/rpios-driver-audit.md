# Reusing Raspberry Pi OS drivers and firmware

Inspection date: September 4, 2026. This is a completed **package extraction and compatibility investigation**, not a claim that a Raspberry Pi OS kernel has booted Omarchy. Nothing was installed on the user's Pi and the public image was not altered.

## What was actually extracted

`image/inspect-rpios-driver-packages.sh` fetches the official Raspberry Pi OS Trixie ARM64 package index. It pins the archive signing-key fingerprint, verifies `InRelease`, checks the index's SHA-256 against that signed metadata, and checks every selected package's SHA-256 before extraction. It extracts data and control scripts for inspection but **never executes maintainer scripts, installs a Debian package, or writes to a boot partition**. The input is the [official Raspberry Pi archive](https://archive.raspberrypi.com/debian/dists/trixie/).

Archive key fingerprint: `CF8A1AF502A2AA2D763BAE7E82B129927FA3303E`. The inspected signed index was dated September 4, 2026. The key was obtained from Raspberry Pi's official HTTPS archive and matched this fingerprint; this is not a claim of an independent offline key ceremony.

| Official package | Version inspected | SHA-256 |
| --- | --- | --- |
| `firmware-brcm80211` | `1:20260519-1~bpo13+1+rpt1` | `c25e13e84be8dbf58b6b3381b4a10ad7e9dbeae101579376f457e0f17e60d902` |
| `bluez-firmware` | `1.2-13+rpt2` | `bfa0cb7a3806fb30a50b9f5756efee4530075aab192ba245758881efb2f24421` |
| `raspi-firmware` | `1:1.20260521-3` | `d8008fb9891ed962a15861d41448e94dc0092648e4928db2772257835fb8e825` |
| `linux-image-6.18.39+rpt-rpi-v8` | `1:6.18.39-1+rpt1` | `b007b959f853ca4d26c53d42d166ca7e8619a31f885d52b334c4cab557965265` |

For comparison, the exact Arch Linux ARM `firmware-raspberrypi-20260311-1` archive was downloaded and its detached signature verified with the official Arch Linux ARM keyring. Signer: `68B3537F39A313B3E574D06777193F152BDBE6A6`. A separate read-only mount of the **published Omarchy image** confirmed its module directory and firmware hashes; it was not merely inferred from today's package recipes.

Extracted third-party payloads remain in ignored `build/` research directories. They are not committed as unexplained binaries or redistributed as a new release. Their included notices are retained. Future repackaging must review the licences for each payload and retain the required notices; the project's MIT licence does not relicense firmware or the Linux kernel.

## Wireless firmware: already reused, and now protected by audits

Arch Linux ARM's `firmware-raspberrypi` package already sources Raspberry Pi's `RPi-Distro/firmware-nonfree` and Bluetooth firmware repositories. The inspected recipe was pinned to firmware commit `9794282eb9f4a2de1f23b41a738926740e975d83` and Bluetooth commit `cdf61dc691a49ff01a124752bd04194907f0f9cd`. [ALARM packaging source](https://github.com/archlinuxarm/PKGBUILDs/blob/2fccb9851adbeafc6ab1f8b2afa07a9f1d37f7cf/alarm/firmware-raspberrypi/PKGBUILD).

The comparisons found:

- Pi 4 Wi-Fi standard and minimal firmware binaries: byte-identical between the official Pi OS and ALARM packages.
- Pi 4 Wi-Fi regulatory data and board NVRAM text: byte-identical.
- `BCM4345C0.hcd` Bluetooth firmware: byte-identical.
- The published Omarchy image's standard Wi-Fi firmware hash is `d608f866582519c0a28d86db43040f4f1b98dd1d153e72e9752586546b4a36c3`; its Bluetooth hash is `51c45e77ddad91a19e96dc8fb75295b2087c279940df2634b23baf71b6dea42c`, matching those compared packages.

A useful extraction trap: the Debian package's default `cyfmac43455-sdio.bin` target is established by `update-alternatives` in its maintainer script. Extracting only the data archive leaves that target absent. ALARM instead installs an explicit symlink to the standard variant under `/usr/lib/firmware/updates/`. A naive directory copy could break firmware that already works. The initial unresolved-path comparison was corrected by comparing the actual standard/minimal payloads separately.

Implemented changes: `firmware-raspberrypi` is now an explicit required official package. The image audit verifies the Pi 4 Wi-Fi binary target, board data, regulatory blob, Bluetooth firmware, and retained licence notice. A regression fixture deliberately breaks the Wi-Fi symlink and must fail the audit. No different firmware is being forced onto working hardware.

## Kernel/media: the important gap to test

The published image contains modules for **`7.2.2-2-aarch64-ARCH`**. Its read-only module inventory includes V3D, VC4, VCHIQ/MMAL and Broadcom audio, but no `bcm2835-codec.ko` matching the vendor package's codec module.

The extracted Pi OS kernel is **`6.18.39+rpt-rpi-v8`**. Its config enables `CONFIG_BCM_VCIO=y`, `CONFIG_VIDEO_CODEC_BCM2835=m`, and Unicam camera support. Its codec module has this ABI identifier:

```text
vermagic=6.18.39+rpt-rpi-v8 SMP preempt mod_unload modversions aarch64
```

VCIO is compiled into that kernel, not provided as a standalone `.ko` to copy. Its codec module belongs to the vendor kernel's matching module/ABI set. Current ALARM source config at commit `2fccb9851adbeafc6ab1f8b2afa07a9f1d37f7cf` does not expose the same vendor VCIO/codec configuration; that source config is for 7.2.3 and must not be mislabeled as the exact published 7.2.2 config. [Raspberry Pi kernel source](https://github.com/raspberrypi/linux), [ALARM config inspected](https://github.com/archlinuxarm/PKGBUILDs/blob/2fccb9851adbeafc6ab1f8b2afa07a9f1d37f7cf/core/linux-aarch64/config).

This is a concrete reason to evaluate a **coherent Raspberry Pi vendor-kernel image variant**, not to force-load a foreign module or overwrite `/usr/lib/modules` on the current image. It may improve media/camera/firmware-interface coverage, but does not prove hardware decoding works in the shipped browser, or that a kernel change repairs an HDMI cable/EDID issue.

## Candidate integration boundary

A vendor-kernel prototype should package the matched kernel, modules, Pi 4 DTB/overlays, and required boot firmware under pacman ownership. It must explicitly adapt our U-Boot/`Image`/`initramfs-linux.img` flow or deliberately select a separately tested native-firmware boot flow. The Debian kernel's image is gzip-compressed and its post-install script calls Debian kernel/initramfs hooks; those scripts must not be executed on Arch Linux ARM as if the distributions were interchangeable.

Before it becomes a default image:

1. Generate an Arch-compatible initramfs and check root-device discovery, console, boot selection, kernel/module ABI, firmware lookup, and package-owned updates.
2. Boot a **spare card** on a 4GB+ Pi 4. Preserve the existing working card as rollback; do not assume an unbootable board can run a software revert.
3. Test V3D/VC4, HDMI/EDID, actual video decode, camera if available, Wi-Fi, Bluetooth pairing, audio playback, USB storage, lock/wake, and hostname persistence after reboot.
4. Compare desktop latency, sustained workloads, temperature, and power against both the current Omarchy image and Raspberry Pi OS. A lower kernel version number alone is neither a performance win nor a regression.
5. Ship the candidate only with exact package provenance, source/licence compliance, and a kernel-aware update route. Never let a later generic `linux-aarch64` upgrade silently replace the selected variant.

This pass supplies the verified donor payloads and inspection tooling, **not an installed or boot-tested vendor-kernel variant**. Pi OS documents `rpi-update` as an experimental/pre-release path, so it is not a shortcut we add to the general Omarchy updater. [Official Pi OS update guidance](https://www.raspberrypi.com/documentation/computers/os.html).

## Repeat the inspection

On a Linux research/build host with `curl`, GnuPG, `gzip`, `sha256sum`, and `dpkg-deb`:

```bash
bash image/inspect-rpios-driver-packages.sh build/rpios-new-inspection
```

Use a new output directory. The script downloads current official metadata, so a future run can resolve different package versions; `packages.tsv`, the signed index, extracted config, module inventory, and control files record what that run actually inspected. A checksum failure stops extraction. Do not run extracted executables or maintainer scripts just because they came from a familiar distribution.
