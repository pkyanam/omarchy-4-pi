# Moving a Pi 4 to Omarchy 4.5

The 4.5 transition starts with a complete fresh image on spare media for Raspberry Pi 4 Model B with 4GB or 8GB RAM. Pi 5 is deferred. The current work is a candidate, not a hardware-qualified release; neither memory variant has a 4.5 hardware validation result here. See [the 4.5 design and validation boundary](omarchy-4.5-pi4.md) and [the work ledger](../plans/omarchy-4.5-pi4.md) for current evidence.

## Existing rolling images: keep the working card

Older Pi images, including `v0.1.0-rc.1`, use rolling Arch Linux ARM packages. The 4.5 candidate uses signed Omarchy stable ARM64 packages and their matching stable ALARM libraries. Switching only mirrors or downgrading selected graphics libraries can leave an inconsistent system. There is no supported automatic rolling-to-stable downgrade.

Do not run a downloaded bootstrap from mutable `main`, rerun `install-rpi4.sh` over an existing installation, or edit the profile to bypass the updater. The new updater refuses a legacy rolling profile before fetching source, refreshing repositories or changing packages. An old installed updater may not contain this protection; running it is not a safe migration procedure. A Git reset cannot roll back installed libraries, the kernel, or the boot partition.

1. Back up personal files and make a recoverable whole-card copy, including the boot partition. Keep the working card untouched as the rollback.
2. Choose an explicitly identified 4.5 Pi 4 candidate when available. Keep its source/recipe identities, package inventory, build manifest, complete build/test logs and compressed-image checksum together. A latest-alpha filename alone does not identify a 4.5 image. Do not treat an unpublished candidate as a release.
3. Verify the downloaded image checksum before writing it to a separate card or SSD. Use its matching Raspberry Pi Imager catalog to retain customization. For split downloads, verify the parts and reassembled image, then follow [the Imager guide](raspberry-pi-4.md#raspberry-pi-imager-2x-customization) to generate/open a local Imager catalog. Never select the working card as the destination.
4. Boot the spare media and complete HDMI or Imager owner setup. Check root growth, hostname, networking/SSH choices, display, input, audio, first login and a second boot. Restore personal data selectively; copying an old `/etc`, package database or entire desktop configuration over the candidate can undo its boot, repository and resource policies.
5. Keep the old card until the new system passes your own checks. Report each 4GB/8GB board independently. A successful source fixture or rootfs audit does not establish physical boot, accelerated rendering/video decoding, or responsiveness.

An eventual in-place transition needs separate validation on a disposable clone, a complete reviewed package transaction and a tested whole-card rollback before instructions can be offered.

## Future updates on a validated 4.5 installation

Normal updates will use the reviewed Pi fork at `pkyanam/omarchy-4-pi`, on a clean `main` checkout tracking `origin/main`. This is a moving-source update contract, not a release-tag selector. The installed profile must contain both `OMARCHY_PACMAN_PROFILE=rpi4` and `OMARCHY_RPI4_PACKAGE_POLICY=stable-4.5`. Its repositories must be ordered `omarchy`, `core`, `extra`, `alarm`: Omarchy uses `https://pkgs.omarchy.org/stable/aarch64`; the others use `https://arm-stable-mirror.omarchy.org/aarch64/<repo>`. Trusted package signatures and protection of the locally adapted core/settings pair are required. Profile markers alone cannot make a rolling installation compatible.

An unpublished `codex/omarchy-4.5-pi4` image keeps its actual candidate branch and source provenance. Fresh installation requires committed tracked source so an interrupted installation can be matched to its checkpoint. The production updater intentionally refuses a candidate branch or local source edits, even with the stable package policy. Do not rename its branch, manufacture `origin/main` refs, delete edits, or write a receipt to bypass the guard. Test a newer complete candidate on spare media until a reviewed production update path is available.

After the production path is available and your installed source meets that contract, back up the card, connect reliable power and close large workloads. Run as the normal desktop user in an interactive terminal:

```bash
omarchy update
```

The updater checks the installed policy before any source/package mutation, prepares source, refreshes the ARM/Omarchy keyrings, performs the coherent full system/runtime transaction, then verifies and installs the matching local Pi core/settings artifacts. It restarts the current shell before migrations. A failed runtime resolution, incomplete core pair, failed installation or shell restart stops completion; core installation is tracked separately from Git HEAD so a failed install remains retryable. Preserve the log and investigate before retrying. Do not reboot immediately after a failed transaction or replay owner provisioning to repair it.

After a successful update and the offered reboot, inspect:

```bash
hostnamectl --static
omarchy-pi-check
omarchy pi report --json
zramctl
systemctl --failed
```

These diagnostics help identify problems; they do not prove audible HDMI playback, a hardware renderer/decoder, or desktop performance. ext4 has no automatic pre-update snapshot here. Retain the whole-card backup, preserve your display/font/effect choices, and keep clock experiments separate; see [tuning and recovery](pi-tuning.md).
