# Inactive AUX hardware flow backport

This directory is a source-reviewed experiment, outside package inputs. It is not installed and does not establish a working radio. See [the decision and integration gates](../../../plans/omarchy-pi-bluetooth-cts-backport.md).

The patch contains exactly the driver hunks of mainline `ca576923c39863ac528427b563ea2f6631703d22` applied to the saved 7.3 driver, with no semantic adaptations. The saved APIs already support it; branch-tip operation-type changes are excluded. The DT opt-in targets the AUX node verified from the captured current FDT. Both are required for this route.

Run from the repository root, with a new child output directory each time:

```bash
python3 tools/pi-experiments/bluetooth-cts-backport/replay.py --output build/upstream-pi/stable-4.5/bt-cts-backport-candidate/review-new
python3 tools/pi-experiments/bluetooth-cts-backport/test.py --output build/upstream-pi/stable-4.5/bt-cts-backport-candidate/test-new >build/upstream-pi/stable-4.5/bt-cts-backport-candidate/test-new-launch.log 2>&1
```

Replay verifies all pinned local source/reference/header/FDT hashes, applies the patch with zero fuzz and no offsets, verifies the output hash and verifies the DT route. No network is used. Tests use the already installed Docker image pinned in `test.py`, no pull, no network, read-only root, disk-backed output/TMPDIR, one compiler invocation at a time, 0.25 CPU, 256 MiB RAM and no swap. There are no kernel/module builds, installs or probes. Missing image/compiler/dtc is a failure, never permission to install anything.

`production.inc` is extracted unchanged from the actual replayed driver before probe; includes alone are replaced with `boundary.h`. `callbacks.inc` dispatches according to the real probe's callback assignments; baseline uses generic 8250 defaults. `serial_out` is the boundary stub that records writes to a register-shift-2 mapped byte array. The harness tests the production functions against those writes. The active-low readiness oracle interprets the resulting CNTL; it does not supply production flow behavior. Generic termios, tty references/locks and em485 allocation are boundary models. This cannot validate kernel compilation, actual registration/locking, hardware FIFO behavior, electrical levels or physical startup/suspend/resume. It exercises the reprogramming reached from those paths via termios and RS485 configuration.

The regression is failure to program active-low hardware flow and resume readiness without CTS interrupts, with loss of manual RTS, throttle or RS485 recovery semantics. The unchanged source is required to compile and return test failure; a compiler failure does not count as red. The fixed source must pass. The compiled overlay must apply to the pinned FDT and a parsed comparison must show exactly one added AUX property.

`manifest.json` pins existing ignored evidence, not vendored source downloads. Keep those inputs with the handoff. All generated files remain in the ignored candidate root; no active recipe references this directory.
