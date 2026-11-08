# Inactive AUX RTS/CTS backport — 2026-11-08

## Result and scope

Prepared an inactive, exact-source backport of mainline `ca576923c39863ac528427b563ea2f6631703d22`, with the matching PFTF AUX-only DT opt-in and production-function host tests. Status: source-reviewed, zero-fuzz replayed, host-tested, overlay compile/application tested against captured current FDT. No matching kernel build, module build, package integration, installation, physical boot or Bluetooth qualification occurred. No working-radio claim is justified.

This implementation lane read root AGENTS, kickoff and the CTS investigation. Its explicit narrower assignment overrides kickoff delegation and AGENTS Kai reporting: no Pi/SSH/probe, GPU/benchmark, install, shared recipe/firmware/old helper edit, staging, commit, push, PR, external message including Kai, or subagent action occurred. Zstd retains the heavy build lease. Only `tools/pi-experiments/bluetooth-cts-backport/`, this plan and ignored `build/upstream-pi/stable-4.5/bt-cts-backport-candidate/` were written.

## Evidence and interval interpretation

Parent evidence is `build/upstream-pi/stable-4.5/bt-cts-candidate/parent-window-1/bt-cts-window-1/`. Reviewed JSONL, actions, trace, profile, result/controller-result, before/after state, trace clock and current FDT. There are 19 JSONL records: armed, 17 samples, finished. Observer and trace exit 0, trace clock mono, exact line-1 BTF/format guard. Four retained events, no reported probe misses or per-CPU drops; CTS-change, TX-loop, RX-loop and write-wakeup have no hits. Before and after JSON compare equal, including binding and taint 0. Raw source paths in controller-result belong to the parent's root-local collector. This lane did not execute them.

All times below are seconds after trace-start, 6184.478472870. GPIO30 is CTS1 from the ALT5 function mapping, regardless of the generic GPIO line label CTS0. All four pinmux reads identify AUX ownership. Selected read intervals:

| Sample | GPIO30 pin read | GPIO30 | BT_ON GPIO read | Requested BT_ON |
| --- | --- | --- | --- | --- |
| 0.4 | 0.400140–0.400788 | high | 0.401267–0.401690 | output high |
| 0.5 | 0.500139–0.500776 | high | 0.501386–0.505916 | output high |
| 0.65 | 0.650151–0.650816 | low | 0.651294–0.651733 | output high |
| 11 | 11.000142–11.000785 | low | 11.001268–11.001707 | output high |

The stop-TX entry is at 0.500824130 with `hw_stopped=1`, about 48 microseconds after the 0.5 pin-read interval ends and before its BT_ON read begins. Start-TX was at 0.380174130; modem-status samples precede both. GPIO30 is low in every later sampled pin interval through 11 seconds and BT_ON is requested high in the corresponding separate GPIO reads. No CTS-change or subsequent TX-loop callback appears. The full interval table and hashes of every retained parent-window file are in `bt-cts-backport-candidate/evidence-review.json`.

These sequential reads are not atomic, do not demonstrate continuous levels between samples and measure neither voltage nor valid HCI traffic. The early unbind/rebind samples include output-low and unclaimed BT_ON states; those must not be described as powered readiness. Even the later requested-high observations do not independently prove controller power. This evidence supports the exact-source missing-modem-IRQ recovery explanation and selecting the existing upstream fix; physical validation remains necessary. The earlier 10/10 plus 4/4 accepted scalar bytes at 115200 belong to an independent window and are not combined electrical proof.

## Primary provenance and exact rebase

Primary fix: [mainline commit ca576923c39863ac528427b563ea2f6631703d22](https://github.com/torvalds/linux/commit/ca576923c39863ac528427b563ea2f6631703d22), Jan Čermák, authored October 1 and committed October 13, 2026; [original submission](https://patch.msgid.link/20261001090432.1045270-1-sairon@sairon.cz). The saved primary JSON under `bt-cts-candidate/reference/` contains the complete driver diff and message. `manifest.json` pins that JSON and every file in the saved UART source subset, matching header API references and current FDT.

The patch reproduces every upstream hunk on `bt-uart-progress-candidate/source/drivers/tty/serial/8250/8250_bcm2835aux.c`. No semantic adaptation or prerequisite is needed: `tty_port_tty` scoped guard, `scoped_tty()`, tty throttle query, UART lock guard, UPF_HARD_FLOW/AUTOCTS/AUTORTS, GPIO lookup and the old uart_port callbacks already exist in the saved 7.3 source/header set. The target `8250_core.c` propagates the custom port callbacks and `8250_port.c` dispatches through them. No missing API is replaced by a shim. Later mainline `d6a0791098bedea41e813db646d21c9ba30004ec` operation-type changes and the branch-tip driver are excluded. Context line positions are regenerated against the saved file; no offset or fuzzy application is allowed.

| Artifact | SHA-256 |
| --- | --- |
| Original saved driver | `36cd6b9a527c56d683f7694ada656dba869028d3e1f998bde73b0229c81f3e18` |
| Backported driver | `2ae07906f5415ceec9e4cac92a0d2f503e3e28150f0f3cdf8115087b34df6fb1` |
| Current captured FDT | `d6a876ec0f13de62ef521b4f90677f528341e19512759f81bb16e211dffb0345` |

The mainline design controls CNTL, not generic MCR AFE: active-low CTS gate and RTS polarity, RTS4 FIFO threshold, cached RXEN/TXEN preservation, manual RTS gating including B0, throttle/unthrottle via RX interrupts, throttle restoration after termios/RS485, RS485 mutual exclusion and RXEN recovery on teardown. Unconfigured ports strip unusable CRTSCTS; CTS-GPIO ports retain software fallback. No global capability or CRTSCTS override is added. The downstream NOMSI polling workaround is not part of this backport.

## Verified DT opt-in

Parsed the actual parent-window `current.fdt` with a small offline standard-library decoder. AUX is `/soc/serial@7e215040`, compatible `brcm,bcm2835-aux-uart`, status okay. Its pinctrl phandle resolves to GPIO32/33/30/31, function 2 (ALT5). Its enabled `brcm,bcm43438-bt` child has max-speed 230400; shutdown phandle resolves to `/soc/firmware/gpio`, compatible `raspberrypi,firmware-gpio`, offset 0, active high, first GPIO line name BT_ON. AUX lacks both `uart-has-rtscts` and `cts-gpios`. PL011 properties were not attributed to AUX.

`pftf-aux-rtscts.dtso` targets that exact path and adds only `uart-has-rtscts`. The upstream driver consumes this property locally into UPF_HARD_FLOW after `uart_read_port_properties()`. The parser comparison after `dtc` plus `fdtoverlay` confirmed every other node/property is identical. This is a proposed overlay source, not a deployed DT package or proof that PFTF/UKI will load it. Keep DMA and existing overlays intact. On a different FDT, refuse automatic reuse and re-review routing/property ownership.

The driver and property form one integration unit. Applying the driver without this opt-in strips CRTSCTS on AUX; applying the property without the driver does not implement CNTL gating. Neither half alone qualifies this board.

## Reproducible verification

Commands and boundary design are in `tools/pi-experiments/bluetooth-cts-backport/README.md`. `replay.py` requires a fresh ignored output child, verifies pinned inputs and patch hash, uses `patch --fuzz=0`, rejects offsets, verifies the exact output hash and checks the current FDT route. `test.py` extracts production functions unchanged, selects callbacks from the real probe assignments and compiles a C harness against boundary stubs. The stubs record actual register writes to a register-shift-2 mapped byte array. An active-low readiness oracle interprets the written CNTL; it does not implement the driver's flow logic.

Final validation: `bt-cts-backport-candidate/test-4-launch.log` and `test-4/test.log`; 62 checks, unchanged driver compiles then fails 30, patched driver passes all 62. Coverage includes active-low readiness transitions, masks/enables, unrelated status/IER preservation, CRTSCTS on/off, manual RTS clear/set, B0 while throttled, re-enabling RTS at nonzero baud, throttle/unthrottle and termios reprogramming, missing tty/state, RS485 exclusion, start/stop polarity, RX-during-TX, teardown without stop, allocation error and NULL termios, unconfigured and CTS-GPIO fallback. Also compiled/applied the overlay and compared parsed FDTs. Earlier `test-1` failed baseline compilation because a boundary-only scope variable was unused; fixed the harness. `test-2` passed 60 checks; `test-3` corrects boundary status constants to match the target header and adds unrelated-status preservation checks. `test-4` revalidates the runner after adding cleanup of its own named container on timeout. Partial logs are retained.

Tests used existing local image `sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2`, GCC 16.1.1, offline/no pull, read-only root, disk-backed output and TMPDIR, sequential compilation, cgroup CPU `25000 100000`, memory 268435456 bytes, swap 0. Final memory peak 80031744 bytes, no OOM events; cgroup CPU usage 128749 microseconds. This does not consume the heavy kernel build lease. No dependencies were installed. Host stubs cannot qualify real locks, registration, FIFO timing, physical suspend/resume, pin voltage, RF or HCI.

## Parent integration and acceptance gates

1. Review this inactive source patch and DT pairing against the complete exact kernel archive, configuration and package lineage. Retain hashes, patch provenance and all existing patches. Build only after Zstd releases the heavy build lease, with bounded concurrency and disk-backed storage. A real matching kernel/header build and appropriate kernel checks are still required; host tests are not an ABI or full compile check.
2. Integrate through the owning kernel recipe with matching kernel and header package versions/release, regenerated source checksums and package manifests, module dependency metadata and initramfs/UKI regeneration where applicable. Never transplant a foreign module or reuse old headers. Include the DT change through the owning DT/firmware package mechanism for this PFTF AUX route; determine its supported overlay loading/application stage and verify the final boot DT contains the opt-in at the AUX node. Do not replace firmware executables or unrelated boot settings to carry it.
3. Preserve installed previous kernel/headers and DT packages, a usable encrypted-root recovery path, root snapshot, and separate ESP/firmware/UKI/DT backups with hashes. Confirm which artifacts root rollback cannot restore. Prove recovery/unlock and a bootable previous entry before changing packages. Parent owns all physical interaction and transactions.
4. Boot the matching candidate and verify release, module identity, AUX driver, tty/HCI mapping and applied DT/pinmux. Require no new taint or errors and unchanged display/storage/DMA behavior. Check termios/baud and real powered CTS recovery without relying on zero software counters. If necessary, use a separately reviewed parent-owned bounded capture or electrical observation; no devmem or userspace UART register pokes follow from this plan.
5. Validate controller initialization, firmware loading, repeated scans, real peripheral pairing/connect/reconnect and usable traffic, cold/warm boots and suspend/resume where supported. Check flow-related throttling and regressions before marking physical success. HCI enumeration alone is insufficient. No scan/peripheral or radio-success claim until these pass.
6. Demonstrate rollback of both kernel/header and DT package inputs, regenerate the matching prior boot payload, restore ESP/firmware artifacts separately when needed, and physically verify the previous boot. Roll back on initialization failure, stalled RX/TX, unexpected RTS behavior, resume failure or boot regression. Restore the coherent previous pair; disabling CRTSCTS is not rollback or a fix.

The candidate is ready for parent review and later matching-build integration, with hardware effectiveness and recovery still pending. Active package recipes remain untouched.

## Parent review checkpoint

Parent reviewed the mainline patch, DT pairing and actual62-check log without rerunning unchanged coverage. Source/overlay/tests and sanitized validation evidence are now tracked. Matching kernel/header and DT package recipe preparation is delegated independently; no build or Pi change is implied. Shared Docker restart/RAM preference is pending with the owner because full-package checks exceed the existing VM's disk-backed memory envelope. Source preparation continues headlessly, and this backport remains inactive.
