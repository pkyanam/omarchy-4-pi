# Pi display preview: offline source investigation

November 8, 2026. Scope: installed runtime/settings 4.5.0-2.4, stable source `/Users/preetham/Code/omarchy-upstream-pi-stable` at `f8e6b769c`. No Pi access, SSH, benchmarks, package builds, installation, staging, commits, or source changes were performed. Parent remains the sole physical Pi owner. This report is the only repository file written by this investigation.

## Finding

Timeout rollback is demonstrated by the supplied log. The absent monitor panel is consistent with invoking the scaling helper directly: `--preview` does not summon a panel. The black desktop is an unexplained visual failure in the captured frame, with insufficient evidence to distinguish a transient resize/decode, a capture issue, or a persistent rendering/layer defect. It is not an intentional scaling behavior in the inspected source. No shipping fix is justified yet.

The exact launch command and its IPC responses are absent from `display-preview-timeout.log`. Thus direct CLI invocation explains the missing panel but is not independently proven by that log. If the parent attempted a panel IPC call, retain its exact command, stdout, stderr, and exit status before attributing the absence to UI code.

## Inputs and ownership

Read the integration and stable AGENTS.md, upstream review AGENTS.md, kickoff, implementation progress (including encrypted reboot success), stable shell development and visual verification guides, and testing reference. Sibling repository status checks were clean at inspection: upstream review `a94119ebc`, stable `f8e6b769c`, packages `474cdba8`, ISO `38f368f`. Package/ISO roots had no AGENTS.md. Integration had the existing untracked kickoff and `.morphess/`; these were preserved. No notifications, ledgers, metrics, or recipes were edited.

The parent supplied installation and reboot evidence; this investigation did not independently query installed files. Relevant owning source is stable `bin/omarchy-hyprland-monitor-scaling`, `shell/plugins/panels/monitor/Panel.qml`, `shell/plugins/background/Background.qml`, and `shell/Ui/BackgroundMedia.qml`. Shared surface remapping is in `shell/Ui/ScreenMoveRemap.qml`; do not change it speculatively because it also affects other surfaces.

## Observed evidence

- Viewed `build/upstream-pi/stable-4.5/optimization/desktop-installed.png`: 1024×768, colorful rocket wallpaper, opaque dark bar, visible icons/text. Its clock reads 6:07 AM.
- Viewed `build/upstream-pi/stable-4.5/optimization/display-preview.png`: 1024×768, black desktop, rendered bar glyphs/text, no visible popup or Keep/Revert controls. Its clock reads 6:12 AM. Bar text/icons are smaller, consistent with the scale change. The strip behind them is also black; this is not proof that only the wallpaper surface failed.
- These are separated captures, not a controlled before/after sequence. The user reports the latter was taken three seconds into preview; the PNG itself does not establish elapsed time, physical-screen appearance, or duration of the black state.
- `display-preview-timeout.log` contains `preview`, exit 1, identical pre/post monitors.lua SHA-256 `58989e90ef481e73401f3af77c76c79b1ef11e6f67e3e3dfce3e7b8bc16b2d31`, restored HDMI-A-1 1024×768@60.004, scale 2, position 0,0, transform 0, and a restoration PASS. No journal, layer inventory, or post-timeout screenshot accompanies it.

## Source trace

### Preview and panel lifecycle

`bin/omarchy-hyprland-monitor-scaling:89` serializes changes with flock. It snapshots the focused monitor and uses partial `hl.monitor` rules, preserving other options. Lines 139–143 install EXIT rollback and apply the candidate. Lines 149–166 check actual compositor mode/scale before announcing readiness. Lines 168–174 print `preview` and read stdin for up to 15 seconds; only the literal `keep` permits persistence. EOF, timeout, and any other answer return failure and invoke rollback. Persistence follows this gate. No call opens the monitor UI or changes wallpaper/theme state.

`Panel.qml:338–350` launches that helper as its own Process and writes `keep\n` or `revert\n` to that Process's stdin. Lines 479–499 enable stdin, consume the readiness marker, show confirmation state, and refresh after exit. Closing the panel rejects its own preview (`onOpenedChanged`, around line 398); readiness received after closing also rejects it. Controls near line 914 are visible only when this instance's `previewReady` is true. A separately launched CLI helper cannot attach itself to the panel's Process by opening the panel later.

The supported monitor target (`Panel.qml:242–252`) declares brightness, state, open/close, toggle, show/hide. It does **not** expose setScale, startPreview, or finishPreview. `shell/Commons/IpcRegistry.qml` allows only declared handler methods. `omarchy-shell omarchy.monitor setScale 1.6` therefore is not a valid public IPC operation. Do not use it as a panel acceptance test.

The monitor manifest is a bar widget. `shell call` uses `panelLoaders` (`shell.qml:1308`), whereas `shell summon` routes bar widgets through `Bar.findPanelWidget`/`summonBarWidget` (Bar.qml around 939–960). Use `omarchy-shell shell summon omarchy.monitor '{}'`, then the actual scale buttons. `shell call omarchy.monitor setScale 1.6` is not a reliable route to this bar-widget instance. Use UI Keep/Revert controls rather than passing string booleans into internal JS methods.

### Scale and wallpaper

For 1024×768, 1.6 is a clean supported scale in both the helper and monitor Model.js. Logical size changes from 512×384 to 640×480; physical pixels remain 1024×768. The matching math rules out this request being silently rounded to a different scale.

`Background.qml` creates a background-layer PanelWindow per Quickshell screen. It anchors all edges, keeps `updatesEnabled: true`, and maps unless suspended or briefly guarded for a screen-origin move. Its comment specifically warns that disabling updates has previously lost a committed buffer; the installed source already contains the protection, so reapplying that fix would achieve nothing.

`ScreenMoveRemap.qml` responds to screen X/Y changes, waits 200 ms, and unmaps for 50 ms. It does not respond to scale or size changes. A pure scale change at origin 0,0 does not intentionally trigger this path. A multi-second black desktop is not explained by its documented normal remap interval alone.

`Background.qml` derives decode size from window logical dimensions × screen.devicePixelRatio. `BackgroundMedia.qml` binds asynchronous Image.sourceSize to that size. A resize or DPR update can initiate another decode, potentially through intermediate dimensions. Qt's whole-number DPR is already acknowledged by the bar source (Bar.qml around 749); it can overestimate physical decode dimensions at fractional scale. This is a plausible transient/memory path, not proof of this blackout. No runtime image status, size timeline, resource failure, or Qt error was recorded.

The background's recovery path responds to image failure by resolving the symlink/theme fallback and only switches when a different path is found. It does not fix a successfully decoded image whose layer buffer stopped appearing. A stale mapped surface, suspended still layer/OWE state, and capture/compositor behavior remain separate possibilities. The screenshot alone cannot select between them. Existing reveal animation is 840 ms nominal and only runs on a background transition; the scaling helper does not request one.

`bin/omarchy-capture-screenshot` delegates to Omasnap. There is no wallpaper-specific blackout in that wrapper. Omasnap internals and the exact original capture invocation are not established here. A camera/physical observation or a second independent capture path is needed to separate display output from capture output.

## Focused offline checks

Executed against stable `f8e6b769c`, with whole output retained before reading:

- `bash test/shell.d/monitor-test.sh`: PASS, 24 model assertions; `/tmp/omarchy-pi-display-monitor-model.log`.
- Extracted and executed the real helper's clean_scale function and real Model.js cleanScale for 1.6 at 1024×768: both return 1.6; `/tmp/omarchy-pi-display-scale-math.log`.
- `bash -n bin/omarchy-hyprland-monitor-scaling`: PASS; `/tmp/omarchy-pi-display-scaling-syntax.log` (empty on success).
- `background-startup-test.sh` and `background-startup-failure-test.sh`: SKIP, no Wayland compositor; logs `/tmp/omarchy-pi-display-background-startup.log` and `/tmp/omarchy-pi-display-background-failure.log`. These provide no graphical acceptance evidence.

Full `monitor-scaling-test.sh` was read, not executed: this Mac lacks flock and GNU sed required by its real Linux command paths. Its existing cases cover EOF rollback, Keep persistence, rejected/unapplied settings, advertised mode selection, and the real 15-second timeout. No fake replacement for flock or timer was introduced to manufacture a pass. No new regression test is warranted without a demonstrated code defect.

## Bounded candidate decision

No patch selected. First establish whether black pixels are transient, persist through rollback, or exist only in capture. Do not restart the shell or force-refresh the background before recording failing state, because that erases the diagnostic distinction.

If a visible persistent blackout has a mapped background layer and no image/decode errors, test an action-time background-only remap as a diagnostic, then consider a background-local event-driven remap on relevant screen geometry/DPR changes. That candidate requires a reproducer and validation that it does not introduce flashes, theme-transition regressions, or extra idle processes. A shared ScreenMoveRemap change would widen scope unnecessarily.

If image loading tracks the blackout, instead consider retaining the last ready still during sourceSize reload or using the compositor's physical mode for decode sizing, preserving the current native-size cap. First demonstrate incorrect dimensions or a reload gap. Neither candidate is implemented or claimed fixed. Preserve still/video backgrounds, multi-monitor layout, Keep/Revert, timeout safety, and existing fonts/style.

## Parent-only validation

Run these only in the authorized live session, with session environment already established. This delegate did not execute them. Parent coordinates the desktop and owns all physical actions.

1. Capture the healthy baseline, monitor state and layers before changing anything:

```bash
sha256sum ~/.config/hypr/monitors.lua
hyprctl monitors -j > /tmp/pi-preview-before-monitors.json
hyprctl layers -j > /tmp/pi-preview-before-layers.json
omarchy-shell omarchy.monitor state
omarchy capture screenshot fullscreen save
omarchy-shell shell summon omarchy.monitor '{}'
```

2. Confirm the panel visibly opens before choosing 1.6 with its scale button. Record a short fullscreen video using `omarchy screenrecord --fullscreen`; stop with `omarchy screenrecord --stop-recording`. Observe the physical display as well as captures. Capture at preview readiness and after roughly 3 and 10 seconds. While failing, record `hyprctl monitors -j`, `hyprctl layers -j`, `omarchy-shell omarchy.monitor state`, and `journalctl --user --since '-2 minutes' --no-pager`. Inspect shell/Qt/image errors and background/bar surfaces; a mapped rectangle alone does not prove a valid buffer. Note whether the panel was open before the scale change and whether it disappears during it.

3. Let this UI-owned preview expire. Verify original full monitor state and unchanged config hash, then capture again. Repeat once using the UI Revert button and once closing the panel. Confirm wallpaper returns or stays visible in every case. Do not infer wallpaper recovery from monitor JSON alone.

4. After preserving the failing evidence, a diagnostic refresh can use the existing still path without changing the symlink:

```bash
background_path=$(readlink -f ~/.local/state/omarchy/current/background)
omarchy-shell background setInstant "$background_path"
```

Only do this for a confirmed still background and record whether it restores the image. Unlike refresh, setInstant increments reloadVersion and can force a decode of the same path; it does not independently prove the root cause. If it fails, preserve state before the parent chooses a shell restart.

5. Keep/persistence is a separate intentionally persistent test. Back up monitors.lua and establish restoration first. Choose 1.6 in the UI, click Keep, verify actual scale and the intended per-output config rule, then have the parent validate session reload/reboot persistence with its existing recovery plan and restore the original baseline. Do not send keep to an unrelated helper or treat opening a panel during a direct CLI preview as ownership of that preview.

6. On a Linux test host, run `bash test/shell.d/monitor-scaling-test.sh >/tmp/pi-monitor-scaling.log 2>&1` and read that log. After any candidate, run focused existing wallpaper/monitor tests plus required actual UI screenshots/video. Tests and screenshots on this Mac do not replace the parent's running-UI gate.

Remaining acceptance: correct UI-owned confirmation, timeout/Revert/close, Keep/persistence, wallpaper continuity, physical-versus-captured output, and any candidate visual regression checks. Timeout restoration and encrypted reboot of the installed packages are already recorded; they do not close these gates.
