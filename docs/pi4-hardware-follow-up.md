# Raspberry Pi 4 hardware follow-up — 2026-09-04

The tester is still using the existing card and has not flashed alpha.8. The exact installed source revision should be read from `/usr/share/omarchy-rpi4/build-manifest.json` before attributing new observations to a particular image.

## Observed

- Raspberry Pi 4 Model B Rev 1.5, AArch64.
- The earlier acceptance report found completed owner provisioning and root expansion, active SDDM, running Hyprland and Quickshell, a loaded V3D module and `renderD128`, network connectivity, a PipeWire sink, a powered Bluetooth controller, and no failed system services.
- Direct Linux sensor readings returned `voltage_alarm=0` and `cpu_temp=43.8C`. This is a healthy snapshot; it does not establish the absence of earlier throttling or replace a soak test.
- SSH succeeds at the default `omarchy.local`, although the tester recalls choosing `omarchy-pi.local` in Imager.
- After an SSH connection, HDMI showed errors that later disappeared. Whether the desktop recovered, and the error text, are not yet established. The timing alone does not establish that SSH caused the display failure.
- The initial display mode was not 1080p.

## Source findings

Imager 2.0.11.1 writes the chosen hostname as `[system].hostname`. Its hostname field accepts letters, digits, and hyphens, not the `.local` discovery suffix. Our parser accepts the same short hostname form and defaults to `omarchy` when the field is absent or empty. A dotted hostname is rejected rather than silently replaced. The private provisioning receipt's `hostname` field distinguishes what was staged from a name changed later; only selected non-secret fields should be shared, never the original preseed file or NetworkManager credentials.

Sources: [Imager customization generator](https://github.com/raspberrypi/rpi-imager/blob/v2.0.11.1/src/customization_generator.cpp), [Imager hostname field](https://github.com/raspberrypi/rpi-imager/blob/v2.0.11.1/src/wizard/HostnameCustomizationStep.qml).

`config/hypr/monitors.lua` selects `preferred` mode with `auto` scaling. No Pi-specific 1080p mode is currently applied. The README's 1080p item was a roadmap item, not a shipped feature, and is now explicitly labeled as planned.

The alpha.8 build completed and its release assets are uploaded. It adds native sensor diagnostics but retains the existing hostname and monitor code; it has not been tested on this physical Pi. A reflash is not yet an evidenced remedy for the new reports.

## Next diagnostic evidence

On the running Pi over SSH:

```bash
hostnamectl --static
sudo jq '{hostname, config_version}' /var/lib/omarchy/imager-preseed.json
jq '{source_commit}' /usr/share/omarchy-rpi4/build-manifest.json
systemctl is-active sddm
pgrep -x Hyprland
hyprctl instances
sudo journalctl -b -k --no-pager | grep -Ei 'drm|vc4|v3d|hdmi|under.?voltage|oom|out of memory' | tail -40
```

If Hyprland is running, use the instance identified above to query its active and supported monitor modes. An SSH shell does not necessarily inherit the graphical session's `HYPRLAND_INSTANCE_SIGNATURE`; a plain `hyprctl monitors` failure over SSH is not sufficient evidence of a compositor failure. Read logs before restarting SDDM, because a restart terminates the current graphical session.

HDMI recovery, actual renderer selection, audio playback, Bluetooth pairing, reboot/shutdown, and longer stability testing remain open. Any monitor-mode change still needs a visual check on the physical display.
