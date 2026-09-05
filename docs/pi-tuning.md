# Pi 4 alpha: gentle defaults, optional clock trials

Target: Raspberry Pi 4 Model B with 4GB+ RAM. The next alpha, `v0.2.0-alpha.2`, is a testing release, not a new RC or a replacement for the stable image. Automated tests cannot establish overclock stability, storage integrity under load, or Raspberry Pi OS performance parity.

## Improvements without overclocking

- **CPU scaling:** a short boot service switches a kernel-default `performance` governor to `schedutil`, or `ondemand` if that is the supported alternative. It preserves other governors and runs before power-profiles-daemon so it does not fight later selections. Opt out with `sudo systemctl disable omarchy-pi-cpu-policy.service`; updates preserve that choice. There is no polling daemon for this default.
- **Memory:** a Pi-specific zram configuration provides logical compressed swap sized at half of RAM (roughly 2GB on a 4GB board). It is not preallocated RAM. Compression uses the kernel's default: the inspected ALARM configuration enables LZO/LZO-RLE but not zstd, so demanding zstd would fail. Later-named local drop-ins retain precedence. App-scope oomd policy is installed explicitly because upstream's ARM package recipe omits it; the compositor's session slice is not made a kill candidate.
- **SD-card pressure:** dirty-writeback thresholds are 32MiB/128MiB; persistent journals are limited to 128MiB with seven-day retention, runtime journals to 32MiB. There is no forced vacuum, volatile-only logging, swapoff, or filesystem durability shortcut.
- **Builds:** makepkg defaults to at most two compiler jobs on a 4GB board, reduced to one when available RAM is below 2GiB. Local zstd package compression uses level 3 and bounded threads instead of archival settings. Explicit caller/user build budgets take precedence. No `-march=native`, global fast-math, or signature bypass is introduced.
- **Recipe stability:** `image/omarchy-pkgs.commit` pins the reviewed recipe revision instead of silently following a moving branch. This does not freeze rolling Arch Linux ARM packages or all recipe source downloads.

The inspected kernel and recipe are linked in [the hardware audit](rpios-driver-audit.md). Linux's Raspberry Pi CPUFreq driver queries firmware clock limits at runtime, so a firmware clock setting can be useful without copying a foreign kernel module. [CPUFreq source](https://github.com/torvalds/linux/blob/master/drivers/cpufreq/raspberrypi-cpufreq.c). An unset zram compression option uses the kernel default. [Generator reference](https://github.com/systemd/zram-generator/blob/main/man/zram-generator.conf.md).

## Establish a stock baseline

```bash
omarchy pi report --json
omarchy-pi-check
omarchy pi benchmark --seconds 30
omarchy pi tune status
```

The CPU microbenchmark runs two SHA-256 workers with small buffers inside the resource-budgeted user scope. It does not write benchmark data to storage. Native temperature and voltage sensors are required; starting at 70°C is refused, reaching 75°C or observing undervoltage stops the sample. JSON records workload version, workers, throughput, and sampled temperature. Compare repeated runs under identical conditions. This is not a video, desktop-latency, or stability benchmark. Do not run several stress tools together.

## Implemented clock profiles

| Profile | Requested settings | Meaning |
| --- | --- | --- |
| `boost` | `arm_boost=1` | Firmware-supported boost; later Pi 4 revisions may select 1.8GHz. Not every revision supports it. |
| `1800` | `arm_boost=1`, `arm_freq=1800` | Explicit CPU target; may exceed an older board's stock clock. |
| `1900` | `arm_boost=1`, `arm_freq=1900` | Experimental CPU overclock. |
| `2000` | `arm_boost=1`, `arm_freq=2000` | Experimental upper bound, not a guaranteed-safe preset. |

Pi OS enables firmware-selected boost on supported boards. The tuner does not set voltage, `force_turbo`, minimum clocks, GPU/SDRAM clocks, or thermal thresholds. Firmware voltage scaling and thermal/undervoltage protections remain in control. Existing clock, voltage, or thermal settings—including included files—cause refusal instead of being overwritten. [Official clock documentation](https://www.raspberrypi.com/documentation/computers/config_txt.html#overclocking-options).

### Preview and apply

Back up the card, provide cooling and a reliable PSU, and have a card reader available. Start with `boost`, not the highest profile:

```bash
omarchy pi tune preview boost
omarchy pi tune apply boost
```

Apply shows the diff and requires interactive `APPLY` confirmation after sudo. There is no unattended risk-acceptance flag. Exact backups are stored under `/var/lib/omarchy/pi-tune/` and as `config.txt.omarchy-before-tune` on the boot partition. Writes use atomic replacement with flushed contents; this cannot guarantee recovery from failing media or power loss. Ambiguous boot paths, conflicting settings, unknown health, hot/undervolted boards, or missing CPUFreq policies cause refusal.

### Reboot and confirm

Reboot manually. **Within ten minutes of boot**, inspect and confirm:

```bash
omarchy pi report
omarchy pi benchmark --seconds 30
omarchy pi tune confirm
```

Confirmation requires an active guard, a new boot, healthy sensors, an unchanged config, and a kernel-exposed maximum supporting the target. This is not proof of sustained actual silicon clock. A kernel/firmware combination that ignores the target must not be declared successful. Unsupported `boost` on an older board will not confirm at 1.8GHz.

While a profile is managed, the guard samples every 15 seconds. It restores the saved boot config on an unconfirmed ten-minute timeout, unavailable native sensors, 75°C temperature, or undervoltage. It also attempts to cap the running CPU at its recorded baseline. Confirmed profiles remain monitored across reboots. Brief faults between samples can be missed, so firmware/kernel protections remain essential. There is no automatic reboot: reboot after rollback to restore firmware clock policy. If the runtime cap fails, the boot file is still restored and the guard logs the need to reboot.

### Restore and recover

```bash
omarchy pi tune restore
sudo journalctl -u omarchy-pi-tune-guard --no-pager -n 30
```

Later boot-config edits are never overwritten. If the file changed after staging, restore attempts the runtime cap and asks you to remove the marked `BEGIN OMARCHY PI CPU TRIAL` through `END OMARCHY PI CPU TRIAL` block manually, then reboot. A modified backup also causes refusal. Archive an older recovery copy before a trial from a different baseline.

**If the Pi cannot boot:** software cannot rescue it. Power off, move the card to another computer, and restore `config.txt.omarchy-before-tune` as `config.txt` on the FAT boot partition. Keep the failed config separately if it contains later display settings. Safely eject and boot again. Unstable clocks can corrupt data despite thermal protection; restore the whole-card backup if necessary.

## Release validation

Tests cover preview non-mutation, included conflicts, ambiguous paths, board/health refusal, backups, repeat-apply refusal, post-reboot confirmation, timeout/heat/voltage rollback, missing CPU controls, restoration idempotence, later-edit preservation, benchmark cleanup, budgets, and setup/audit integration. The image gate requires the implementations and policies and rejects an already-overclocked image.

Before promotion, boot the real 4GB Pi at stock clocks. Verify `zramctl`, `swapon --show`, `systemctl --failed`, CPU policy, HDMI/lock/wake, networking/audio, and the Imager hostname after reboot. Test clocks only after that baseline and recovery preparation. Hardware performance parity remains unmeasured. This alpha keeps the established ALARM boot/driver path; the vendor-kernel/media experiment stays separate.
