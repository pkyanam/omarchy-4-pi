# Omarchy 4 Pi

Use this guide for end-user repairs and customization on Raspberry Pi hardware. Confirm the machine with `omarchy-hw-raspberry-pi`; do not apply Pi settings to other ARM systems. The 4.5 port targets Pi 4 Model B with 4GB or 8GB RAM. Pi 5 qualification is separate.

## Start with evidence

Run `omarchy-pi-check` and `omarchy pi report --json`, then inspect only the logs and services relevant to the reported problem. `omarchy-pi-display`, `hostnamectl --static`, `systemctl --failed`, `journalctl -b`, and `zramctl` can help narrow it down. Distinguish a running service from audible sound, paired Bluetooth hardware, accelerated rendering or working video decode. A missing legacy `/dev/vcio_gencmd` device alone does not prove a power fault; use the native sensor report.

Keep passwords, keys, NetworkManager connection secrets and raw provisioning data private. `/var/lib/omarchy/imager-preseed.json` can contain sensitive setup data; do not paste it into a report. Select only a needed non-secret field such as `sudo jq '{hostname}' /var/lib/omarchy/imager-preseed.json`.

## Make repairs survive updates

Follow the main skill's configuration and privilege rules. Put user changes in `~/.config/`, back up the affected file, preserve unrelated display/font/theme choices, and verify the actual result. Read `$OMARCHY_PATH` for reference. Do not patch the package-owned `/usr/share/omarchy/` tree as a lasting repair. A code defect belongs in a development checkout of `https://github.com/pkyanam/omarchy-4-pi`, following its `AGENTS.md`.

For missing display modes, diagnose EDID and the cable/adapter before forcing timings. Use the port's reversible `omarchy-pi-display` commands; the `nec-ea243wm` preset is for that monitor only. Keep the original boot configuration recoverable before any boot-level experiment.

## Preserve the Pi update and boot contracts

The published 4.5 image uses a clean Pi-fork `main` checkout tracking `origin/main`, the `stable-4.5` package policy, signed Omarchy ARM packages and matching ALARM libraries. Use `omarchy update`. Do not replace the locally adapted core/settings pair with upstream core packages, switch to rolling mirrors, perform partial graphics-library downgrades, or bypass an update refusal by changing branch/profile markers or receipts.

Older rolling images require a fresh 4.5 image on spare media. Keep the old card and restore personal data selectively. An unpublished candidate branch is deliberately outside the production updater contract. Re-running the installer over an existing system is not a repair path; its `--resume` option is only for a matching interrupted fresh installation.

Preserve Raspberry Pi firmware, U-Boot, `linux-aarch64`, VC4/V3D and the existing partition layout. Do not install Limine, use another ARM family's boot hooks, copy kernel modules from Raspberry Pi OS, or claim that a browser flag proves hardware decode. The default ext4 image has no automatic Snapper rollback; a Git reset does not roll back system packages or boot files.

## Leave room for the desktop

Keep stock clocks, thermal protections, the existing compressed-swap policy and conservative effects unless the user requests a measured experiment. Extra RAM on the 8GB model does not make its CPU or GPU faster. Use `omarchy pi run --plan -- COMMAND` to inspect the workload budget, then `omarchy pi run -- COMMAND` for builds or a separate heavy agent session. The scope is resource control, not a security sandbox, and hitting its memory ceiling can terminate work.

After a fix, rerun the relevant diagnostic and exercise the affected behavior. Report what changed, what was verified, what remains uncertain, and how to undo the change. Do not call the system fully qualified from a health-check pass alone.
