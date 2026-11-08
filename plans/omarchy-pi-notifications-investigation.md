# Stable notification placements investigation

## Scope and provenance

Offline source investigation on November 8, 2026. The owning checkout is `/Users/preetham/Code/omarchy-upstream-pi-stable`, whose HEAD was exactly `f8e6b769cecbc5338ef14a90f04849f117a149c2`; notification sources initially matched that commit and the checkout was clean. The parent reports installed runtime/settings `4.5.0-2.4` built from that source and a restart warning: `QML Service shell/plugins/notifications/Service.qml[23:1]: Binding loop detected for property placements`, location `545:3`. This investigation did not independently inspect installed files or reproduce the warning in Qt.

Read the owning `AGENTS.md`, `agents/skills/shell-dev.md`, `agents/skills/visual-verification.md`, `agents/skills/motion.md`, `docs/notifications.md`, testing guidance, notification sources and tests, and the integration workspace's `plans/omarchy-pi-implementation-progress.md`. The progress report is absent from the stable checkout and was read in `/Users/preetham/Code/omarchy-4-pi`. No Pi access, SSH, physical activity, benchmarks, messages, staging, commits, pushes, PRs, package changes, monitor/wallpaper changes, ledger changes, or metric changes were performed.

## Source cause

The reported stable line 545 declares `placements`. Its body copies `layout.placements` and merges departure placements; the copy itself does not mutate its input. A concrete synchronous feedback path exists elsewhere:

1. `Service.qml` publishes `placements`; each Toast binds `place` to its entry.
2. `Toast.qml`'s `deedArea.shown` depends on `card.place.front` for a collapsed deck. Becoming the front card can show action/code buttons and change `deedArea.wanted`.
3. `targetHeight = fixedHeight + deedArea.wanted` consequently changes. The Toast delegate's `onTargetHeightChanged` synchronously calls `service.noteHeight` on the visible output.
4. Original `noteHeight` can call `commit`, which calls `snapshot`, which reads `placements` through both its loop and `at()` while the placements evaluation is still propagating. Its fresh-card path can instead call `land`, invalidating layout through `layoutRevision` during that propagation.
5. The resulting target layout uses the changed measured heights and feeds placements back to the delegates.

This explains the exact binding named in the warning and justifies fixing reentrant height feedback in the shared notification service. It is a source-supported attribution, with a regression demonstrating the synchronous reentry; Qt runtime confirmation against the parent's triggering notification remains an acceptance gate. No evidence here ties it specifically to Raspberry Pi hardware, package compilation, or the unrelated display-preview problem. The initial insertion's `arriving` fast path is already separate: it writes the initial measurement for the insertion's own upcoming retarget without taking a snapshot.

## Changes in the stable owning source

- `shell/plugins/notifications/Service.qml`: queue non-insertion height reports with `Qt.callLater`, keeping the latest measurement and at most one pending callback per card. Once bindings unwind, discard reports for removed rows, ignore unchanged heights using the existing half-pixel tolerance, and execute the existing fresh-card landing or shared-scene commit path. Keyboard reach is checked after the height is applied. The arrival measurement remains synchronous so `showRow` can compute landing geometry immediately after insertion. Reports that return to the stored height before delivery correctly cause no move.
- `test/shell.d/notifications/logic.cjs`: extend the existing behavioral harness to reject synchronous snapshot reentry, exercise latest-height coalescing, cancellation by a return to the original height, removal before delivery, immediate insertion measurement, fresh settled landing, and keyboard reach rechecking.

The notification server, model, grouping, action routing, lifetime/quiet/persistence policies, display selection, layer surfaces, and shared scene clock remain in place. This patch changes when height feedback enters that clock; it does not disable notifications, actions, animations, or any platform's feature. There is no polling, recurring timer, external process, or new service. A deferred callback exists only after a height report. Existing relative-time and expiry timers are unchanged.

## Correctness and idle CPU implications

Synchronous layout reentry can leave geometry stale or produce repeated invalidations during notification changes. Deferring measured-height feedback lets the layout binding complete before a new snapshot and retarget; per-card coalescing also avoids processing superseded heights. This is a correctness fix with plausible reduction of redundant work during changes. A binding-loop warning alone does not demonstrate continuous execution, an idle CPU spin, a crash, or any measured performance/energy cost. No CPU, frame, energy, or throughput savings are claimed. There is no new scheduled activity when notification geometry is unchanged. Parent runtime observation must establish whether the warning disappears and whether the layout settles normally.

## Focused validation

- Added the regression before changing `Service.qml` and ran the real existing JS harness against the original source: exit 1, `height feedback re-entered the placements evaluation`, from original `noteHeight` calling the modeled snapshot boundary synchronously. Full log: `/tmp/omarchy-pi-notifications-base.log`.
- Candidate `bash test/shell.d/notifications-test.sh`: the complete notification JS logic passes, then the wrapper fails at state preparation because macOS `chmod` rejects the GNU-style invocation. An isolated archive of pristine `f8e6b769c` produces the identical failure. Logs: `/tmp/omarchy-pi-notifications-focused.log` and `/tmp/omarchy-pi-notifications-baseline-suite.log`.
- With the already-installed GNU coreutils directory prepended to PATH, candidate state preparation passes, then the legacy migration cleanup assertion fails because the old timestamp JSON remains. The migration uses `find -regex`; macOS find's default regex behavior differs from the Linux environment. An isolated pristine archive with the same tool selection fails identically. Logs: `/tmp/omarchy-pi-notifications-gnu-suite.log` and `/tmp/omarchy-pi-notifications-baseline-gnu.log`. These are existing host compatibility limits, left outside this patch; the full wrapper is not claimed green.
- After completing the fresh-card/keyboard coverage, `node test/shell.d/notifications/logic.cjs` passes (exit 0, `notification logic: passed`), including the full existing notification logic and the added regression. Final log: `/tmp/omarchy-pi-notifications-logic-final.log`.
- `git diff --check` passes. No shared code was changed, so no aggregate suite was run. Quickshell and qmllint are unavailable locally. The Node harness executes actual service functions with modeled ListModel/event-loop/external boundaries; it does not emulate Qt binding dependency tracking or establish live warning removal.

## Parent acceptance gates

1. Review/integrate the two unstaged notification source/test edits from the stable checkout and run `bash test/shell.d/notifications-test.sh` once on a compatible Linux environment, retaining its full log. Preserve exact candidate provenance when packaging; no recipe edits are part of this investigation.
2. On the parent's authorized desktop/VM, run the candidate through the normal shell launcher, restart with persisted actionable notifications, and inspect the full session log for this placements warning and other QML errors. Repeat the original triggering restart conditions as closely as available; do not assume the one warning proves an idle spin.
3. Exercise single and grouped actionable cards: a new front card, an older card promoted by dismissal, replacements, multiple groups, code/action buttons, expanded bodies, pointer hover and keyboard selection. Confirm heights converge, buttons remain visible/clickable, and no clipping, overlap, stale hit targets, or lost focus occurs. Check keyboard reach after buttons grow the selected card.
4. Verify ordinary expiry, critical persistence, held arrivals/release, DND/history/replay, restored actions, immediate key dismissals, and display/fullscreen surface behavior remain correct. Where available, check display handoff with queued measurements and late icon/text reflow.
5. Follow the repository visual-verification guide: compare reference and candidate screenshots, and inspect a short recording around front-card changes and interrupted transitions. Reduced-motion behavior and shared-clock settling must remain intact. All live visual and physical acceptance belongs to the parent and remains unperformed here.
6. If the parent evaluates idle CPU, use its separately owned controlled measurement workflow and label workload/provenance. Source inspection and a clean log are not a performance result.

## Handoff

Only the stable checkout's `shell/plugins/notifications/Service.qml` and `test/shell.d/notifications/logic.cjs` were edited there. This report is `/Users/preetham/Code/omarchy-4-pi/plans/omarchy-pi-notifications-investigation.md`. All edits are left unstaged and uncommitted for parent integration. Offline source work is complete; live Qt/visual acceptance and any performance claim remain open.
