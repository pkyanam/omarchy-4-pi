# Raspberry Pi 4 hardware follow-up — 2026-09-04

The tester is using alpha.7: the installed manifest reports source revision `4bbf806039d274e3402f7c29e62789959b808097`. Alpha.8 has not been flashed.

## Observed

- Raspberry Pi 4 Model B Rev 1.5, AArch64.
- The earlier acceptance report found completed owner provisioning and root expansion, active SDDM, running Hyprland and Quickshell, a loaded V3D module and `renderD128`, network connectivity, a PipeWire sink, a powered Bluetooth controller, and no failed system services.
- Direct Linux sensor readings returned `voltage_alarm=0` and `cpu_temp=43.8C`. This is a healthy snapshot; it does not establish the absence of earlier throttling or replace a soak test.
- The tester entered `omarchy-pi` in Imager. Both the saved provisioning receipt and `hostnamectl --static` report `omarchy-pi`, confirming the chosen name was staged and is currently configured. Earlier discovery at `omarchy.local` remains unexplained; the evidence does not support blaming hostname entry or claiming provisioning overwrote the name.
- SDDM is active and Hyprland reports a running instance. After an SSH connection, HDMI showed errors that later disappeared. The supplied kernel excerpt repeatedly reports `HDMI Sink doesn't support RGB, something's wrong.` and `HDMI: Unknown ELD version 0`. The timing alone does not establish that SSH caused the display failure, and a running compositor does not establish healthy scanout.
- The tester changed scaling from 2× to 1×. Hyprland then reported `HDMI-A-1` at 1024×768, 60.004 Hz, scale 1, with empty make/model fields. Available modes were only 1024×768, 800×600 (two refresh rates), 848×480, and 640×480. `hyprctl configerrors` returned no errors. The monitor model/native resolution and connection path remain to be collected.
- Subsequent checks returned zero EDID bytes for `/sys/class/drm/card1-HDMI-A-1/edid`. The monitor is a NEC MultiSync EA243WM, native 1920×1200; the cable/adapter path is still unknown.

## Source findings

Imager 2.0.11.1 writes the chosen hostname as `[system].hostname`. The receipt confirms that this handoff preserved the tester's short hostname correctly. Only selected non-secret receipt fields should be shared, never the original preseed file or NetworkManager credentials.

Sources: [Imager customization generator](https://github.com/raspberrypi/rpi-imager/blob/v2.0.11.1/src/customization_generator.cpp), [Imager hostname field](https://github.com/raspberrypi/rpi-imager/blob/v2.0.11.1/src/wizard/HostnameCustomizationStep.qml).

`config/hypr/monitors.lua` selects `preferred` mode with `auto` scaling. No Pi-specific 1080p mode is currently applied. The README's 1080p item was a roadmap item, not a shipped feature, and is now explicitly labeled as planned.

The same config independently sets `GDK_SCALE=2`. That can affect GTK application sizing even when the monitor scale is 1; it does not determine the HDMI pixel mode.

Linux's [HDMI state helper](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/display/drm_hdmi_state_helper.c) emits the RGB warning when display capability data lacks RGB support. Its comment describes failed EDID reads or noncompliant EDID as possible causes and allows RGB as a fallback. The [audio ELD parser](https://github.com/torvalds/linux/blob/master/sound/core/pcm_drm_eld.c) rejects unrecognized ELD versions. These findings support inspecting capability reads and the HDMI connection path; they do not prove a defective cable, monitor, or driver.

The low-resolution mode list and empty monitor identity are consistent with Linux's [fallback mode generation](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_probe_helper.c): when a connected display supplies no modes, the probe helper adds standard modes up to 1024×768. This points to missing usable EDID/mode discovery rather than monitor scaling. Next, check EDID byte count and retest capability discovery after reseating a direct HDMI connection with the display powered on and its input selected. A nonempty EDID still needs validation; byte count alone does not establish correctness.

The alpha.8 build completed and its release assets are uploaded. It adds native sensor diagnostics but retains the existing hostname and monitor code; it has not been tested on this physical Pi. A reflash is not yet an evidenced remedy for the new reports.

## Next diagnostic evidence

On the running Pi over SSH:

```bash
hyprctl -i 0 -j monitors all | jq '.[] | {name, make, model, width, height, refreshRate, scale, currentFormat, availableModes}'
hyprctl -i 0 configerrors
for d in /sys/class/drm/card*-HDMI-A-*; do
  echo "${d##*/}: $(cat "$d/status")"
  printf 'EDID bytes: '; wc -c < "$d/edid"
done
```

The tester reported one Hyprland instance, so index 0 selects it explicitly from SSH. An SSH shell does not necessarily inherit the graphical session's `HYPRLAND_INSTANCE_SIGNATURE`; a plain `hyprctl monitors` failure over SSH is not sufficient evidence of a compositor failure. Record the monitor model/native resolution and whether the connection is direct or passes through an adapter, dock, switch, or receiver. Read logs before restarting SDDM, because a restart terminates the current graphical session.

HDMI recovery, actual renderer selection, audio playback, Bluetooth pairing, reboot/shutdown, and longer stability testing remain open. Any monitor-mode change still needs a visual check on the physical display.

## NEC EA243WM temporary native-mode test

NEC's [manual](https://assets.sharpnecdisplays.us/documents/usermanuals/ea273wm_ea243wm_usermanual.pdf) recommends 1920×1200 at 60 Hz. With EDID unavailable, an explicit modeline is a possible workaround, not a repair of capability discovery. The following candidate uses the standard 154 MHz reduced-blanking timing from Linux's [DMT mode table](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_edid.c) and Hyprland's documented [custom modeline interface](https://wiki.hypr.land/configuring/core/monitors/modes/).

Run over SSH with the display visible. It attempts native resolution for 20 seconds, then requests the previously working 1024×768 mode. No config file is changed. Keep SSH connected throughout; if the compositor stops responding, the restore command cannot recover it. This candidate has not yet been verified on the physical monitor.

```bash
(
  trap 'hyprctl -i 0 eval "hl.monitor({output=\"HDMI-A-1\", mode=\"1024x768@60\", position=\"auto\", scale=1})"' EXIT
  hyprctl -i 0 eval 'hl.monitor({output="HDMI-A-1", mode="modeline 154.00 1920 1968 2000 2080 1200 1203 1209 1235 +hsync -vsync", position="auto", scale=1})'
  sleep 20
)
```

Only persist a monitor-specific override after the tester confirms clear, stable output and the expected resolution. Do not apply this timing as a universal Pi image default or assume it restores HDMI audio capabilities.
