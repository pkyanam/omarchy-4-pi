# Monitor preview rollback after UI ownership loss

## Scope and evidence

Implemented in `/Users/preetham/Code/omarchy-upstream-pi-stable`, based on `1c3339a73`. No notification changes, physical board operations, SSH, package builds, staging, commits, pushes, external messages, or delegated agents were used.

The parent reproduced this on installed Omarchy 4.5.0-2.4 (`f8e6b769c`), kernel 7.3-32.1: summon the monitor panel, send Right/Right/Right/Return to select 1.6, then observe scale 1.6 at three seconds and still at approximately eighteen seconds, with no scaling helper remaining and an unchanged monitors.lua hash. Evidence is in `/Users/preetham/Code/omarchy-4-pi/build/upstream-pi/stable-4.5/optimization/ui-owned-preview*.log` and the adjacent screenshots. The three-second screenshot shows a black desktop and no monitor panel; the top bar remains visible. This establishes failed rollback, not the exact screen lifecycle event that triggered it.

## Cause established from source

`Panel.qml` owns `displayPreview`, a Quickshell `Process` that previously ran the entire scaling transaction. `bin/omarchy-hyprland-monitor-scaling` put rollback in that child's Bash EXIT trap. EOF, ordinary TERM and the fifteen-second read timeout work while that child survives, explaining the earlier successful CLI-only experiment.

Quickshell's [Process destructor](https://github.com/quickshell-mirror/quickshell/blob/master/src/io/process.cpp) explicitly calls `QProcess::kill()` when its QML owner is destroyed. On Unix this forcibly kills the child; Bash cannot execute any trap after SIGKILL. The upstream source was inspected during this task; the installed Pi binary was not inspected. In this checkout, the monitor manifest registers `Panel.qml` as a bar widget. `Bar.qml` creates `BarPanel` instances from `Quickshell.screens`, owns horizontal/vertical WidgetPools in each surface, and loads widgets in WidgetHost loaders. Removing a screen or unloading a widget therefore removes the corresponding panel and its Process. Merely resizing a surviving screen does not prove destruction. The supplied journal does not establish whether screen replacement, widget unloading, or another shell lifecycle event occurred on that run. The source proves the unsafe ownership boundary, and a behavioral regression reproduces the stranded live scale by killing exactly that owner process.

## Changes

- Preview invocations now replace the UI-owned child with `python3 shell/plugins/panels/monitor/preview.py`. That launcher starts the existing Bash transaction in a separate session and waits for its exit. The QML protocol remains `preview` on stdout and `keep`/`revert` on stdin.
- The worker inherits the original pipes directly. Killing the launcher or its process group cannot kill the transaction. Closing the UI's writer yields EOF and rollback; if a writer survives, the existing fifteen-second read deadline still rolls back. No process or timer runs after the transaction finishes, and no idle polling service is introduced.
- The worker owns the existing flock, applies and verifies the candidate, waits for confirmation, persists on Keep, and releases the lock only after commit or restoration. A recreated panel or CLI request cannot capture a preview as its baseline while another transaction is active. Every request has its own pipes; there is no shared Keep token to acknowledge a later request accidentally.
- PIPE joins the termination traps so losing the stdout reader before the `preview` message restores the rule too. Keep still persists atomically through the existing config rewrite; rejection, timeout and failed persistence retain the existing restore behavior.
- The launcher is in the monitor plugin directory because the Pi recipe copies `shell/` into the package but omits the repository's maintenance `scripts/` directory. Python is already a runtime dependency of the packaged installation; no package replacement is needed.

The worker is independent of UI process ownership, not immune to an explicit SIGKILL directed at the worker itself, an entire session cgroup being forcibly killed, or an unavailable compositor. Those cases cannot be repaired by a Bash trap. This change addresses the ordinary Quickshell Process destructor boundary without adding a persistent service or changing the UI's features. It does not claim to repair the separate black-wallpaper/screen recreation behavior.

## Local validation

Used the existing local `omarchy-pi-test:4.5` ARM Linux Docker image, network disabled, one CPU, 1 GiB memory. No packages were built. The compositor boundary is the existing fake hyprctl; all transaction execution, signals, process sessions, pipes, flock, deadlines, config writes and rollback are real.

- `test/shell.d/monitor-scaling-test.sh` passed: extended with explicit rejection and owner-loss regression cases. These kill the UI-owned process group before readiness or after readiness, close pipes or retain stdin beyond the real deadline, verify restoration and unchanged disk contents, reject a competing request, verify lock release, and successfully Keep a subsequent preview. Existing advertised-mode, failed-apply, unsafe-persistence, EOF, timeout, scale and GDK tests remain in the suite. Final output: `/tmp/omarchy-monitor-scaling-verified-test.log`.
- The owner-loss regression was also run against a temporary copy of the HEAD helper with the same compositor fixture. It failed with `AssertionError: UI-owned process died and left unconfirmed scale active`. Log: `/tmp/omarchy-monitor-scaling-base-test.log`. No tracked file was reverted for that experiment.
- Existing monitor model and monitor state suites passed. Logs: `/tmp/omarchy-monitor-model-test.log`, `/tmp/omarchy-monitor-state-test.log`.
- `git diff --check` passed. An intermediate run was invalidated by editing the mounted test file while Bash was still reading it; the final run uses the settled file.

No live UI validation was performed here: the parent owns the board and explicitly prohibited physical operations. The commands below are the remaining physical validation, not completed evidence.

## Parent physical validation commands

Build/install the parent's candidate package from this source and confirm the installed command and `shell/plugins/panels/monitor/preview.py` are both present. Start from the parent's restored scale 2 and idle baseline. Run all commands below in the real user's graphical session. Save screenshots and command output in the parent's artifact directory.

```bash
artifact_dir="$HOME/monitor-preview-validation"
mkdir -p "$artifact_dir"
hyprctl monitors -j >"$artifact_dir/before.json"
sha256sum "$HOME/.config/hypr/monitors.lua" >"$artifact_dir/before.sha256"
omarchy-shell shell hide omarchy.monitor
omarchy-shell shell summon omarchy.monitor '{}'
wtype -k Right -k Right -k Right -k Return
sleep 3
hyprctl monitors -j >"$artifact_dir/preview-3s.json"
ps -eo pid,ppid,pgid,args >"$artifact_dir/preview-processes.txt"
omarchy capture screenshot fullscreen save
sleep 15
hyprctl monitors -j >"$artifact_dir/after-timeout.json"
sha256sum "$HOME/.config/hypr/monitors.lua" >"$artifact_dir/after-timeout.sha256"
omarchy capture screenshot fullscreen save
```

Verify scale returns to 2, disk hash remains identical, and the worker and launcher disappear. Confirm the live source is the installed candidate. Review both screenshots for panel/bar recovery, wallpaper, focus and layout. A black wallpaper remaining after rollback is a separate observable issue; retain its evidence.

Repeat the same preview and explicitly choose Revert (the confirmation row starts on Keep; Down then Return selects Revert). Repeat and use Return on Keep; verify the rule persists, the worker exits, and waiting another eighteen seconds does not undo the kept setting. Restore the parent's chosen baseline after the Keep test.

To exercise the exact Process destruction boundary without killing the whole shell, start another preview and identify its launcher from `ps -eo pid,ppid,pgid,args`: the command is `python3 .../shell/plugins/panels/monitor/preview.py ... --preview-transaction --preview ...`. Set `launcher_pid` to that one verified numeric PID and kill only it:

```bash
kill -KILL "$launcher_pid"
sleep 18
hyprctl monitors -j >"$artifact_dir/after-launcher-loss.json"
sha256sum "$HOME/.config/hypr/monitors.lua" >"$artifact_dir/after-launcher-loss.sha256"
omarchy capture screenshot fullscreen save
```

The detached Bash `--preview-transaction` worker must restore scale 2 and exit even if the UI no longer offers confirmation. During a pending preview, `omarchy-hyprland-monitor-scaling 3` must fail with `Another display change is in progress`; it must not mutate either the live candidate or the saved rule. After rollback, a newly summoned panel must preview and Keep successfully. Also exercise one advertised resolution change with timeout and one with Revert, recording before/after width, height, refresh rate and scale. Do not synthesize an unadvertised mode. Preserve the parent's existing idle policy throughout.
