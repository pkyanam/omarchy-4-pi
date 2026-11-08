# Pi Bluetooth baud-transition candidate — 2026-11-08

## Upstream solution and ownership

The durable solution belongs in Linux Bluetooth/serial or the firmware device tree, according to an HCI/UART trace of the failing initialization. First establish whether the controller receives and answers the initial vendor baud command at the initial speed, and whether its power/reset and RTS/CTS sequence matches the mainline driver. Correct that handshake upstream before qualifying a Pi workaround. Neither an arbitrary delay, a lower advertised speed, a blanket `skip-init` implementation nor hiding Bluetooth is justified by the saved evidence.

One independent Linux error-handling defect is reproducible without hardware: serdev setup logs a failed controller baud command and continues into protocol setup. The candidate returns that error immediately. It prevents further initialization on an uncertain transport and preserves the original failure; **it does not repair controller initialization or demonstrate working Bluetooth**.

The owning recipe is `../omarchy-pkgs-pi/pkgbuilds/linux-omarchy-aarch64/`, which produces `linux-omarchy`, `linux-omarchy-headers` and the NVIDIA companion. The x86 `linux-omarchy/` recipe is a different kernel and is not the owner. Candidate patch: `0670-bluetooth-serdev-stop-on-baudrate-error.patch` in the aarch64 recipe directory. It is deliberately absent from `PKGBUILD` sources/checksums and cannot enter an ordinary package build yet. Source test: `../omarchy-pkgs-pi/tests/linux-bluetooth-baud.py`.

If accepted, the kernel owner should add the patch to the normal source list with both checksum arrays updated and a new package release, after reconciling the reviewed `32.1` recipe with the owning recipe's still-`32` release field. Do not overwrite an existing package filename or replace the installed `32.1` with the older recipe baseline. `raspberrypi-4-support` owns platform checks/build limits and DDC permissions; it should not install a replacement HCI module or service to bypass Linux. Firmware routing changes belong to firmware/media integration (including the ISO firmware preparation), with the necessary DMA overlay preserved. Runtime/settings do not own this UART failure.

## Scope and initial state

Read the workspace and sibling runtime AGENTS instructions, optimization kickoff, discovery and later release-ledger updates, driver report/preflight, reviewed-kernel installation evidence and reconciliation report. The package and ISO trees have no AGENTS.md files. Latest task boundaries take precedence over the kickoff's broader installation/delegation authority. No Pi access, SSH, installation, reboot, kernel build, push, PR, external message or subagent was used. No ledgers or measurement files were edited. All observations below are saved evidence or offline source results, not a new live qualification.

Sibling heads at inspection, with clean working trees:

| Tree | HEAD |
| --- | --- |
| omarchy-upstream-pi | `a94119ebc3c791cc3aa246da9aa519dd800f6398` |
| omarchy-upstream-pi-stable | `f8e6b769cecbc5338ef14a90f04849f117a149c2` |
| omarchy-pkgs-pi | `db4db9894ddc11838724928846b134699a6108b3` |
| omarchy-iso-pi | `38f368f961f1d5d3d28b39630856e79ebca3100e` |

This workspace already contained untracked `.morphess/` and `plans/omarchy-pi-optimization-kickoff.md`; both were preserved. No commits were made or rewritten.

## Exact source and device tree

The local archive `build/upstream-pi/linux-7.3.tar.xz` has SHA-256 `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`, matching the reviewed recipe's first SHA-256. Its BLAKE2b also matches the owning recipe. Selected files were extracted into `/tmp/omarchy-bt-73-source`; no whole-tree kernel extraction or build was needed. The manifest identifies upstream v7.3 commit `c03c1a14507dfaf8b856c2608f9ac216021fc222`. Extracted hashes agree with the saved manifest where present:

| Exact v7.3 file | SHA-256 |
| --- | --- |
| drivers/bluetooth/hci_serdev.c | `7ea43973798689b060eb9d7ca4359e87dcd8aa2b49f835cab4d5eb194c10b206` |
| drivers/bluetooth/hci_bcm.c | `e00bbc0a931d5a7bd930dd98b6cc08ebb0c697df741588920f0ab8344c905fc2` |
| drivers/bluetooth/btbcm.c | `0d0f3904ce577e5f35983e8d834e1ecf47eee9590dc7557c92e41ca988625e7c` |
| drivers/tty/serial/8250/8250_bcm2835aux.c | `36cd6b9a527c56d683f7694ada656dba869028d3e1f998bde73b0229c81f3e18` |
| arch/arm/boot/dts/broadcom/bcm2711-rpi-4-b.dts | `c69ee77b38dc3c3b7edff87b4cd24f3ed1d54e5b73154d65a84249d53a51feb1` |

The exact [serdev source](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/drivers/bluetooth/hci_serdev.c) and [Broadcom source](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/drivers/bluetooth/hci_bcm.c) were also checked against the pinned upstream reference. No owning-recipe patch references `hci_serdev.c`, `hci_bcm.c`, `btbcm.c` or `8250_bcm2835aux.c` before this candidate. This is source identification, not a reconstruction or authentication of every byte of the installed kernel.

Parsed both saved DTB binaries directly as big-endian flattened device trees, instead of assuming the mainline board DTS is what PFTF supplied:

- `build/upstream-pi/installed-repair/running.dtb`: SHA-256 `b027c70319bace99b8bcafa72ce21e52859afd3e234e206e1fe9a65347f883e3`.
- `build/upstream-pi/stable-4.5/drivers/current-uncapped.dtb`: SHA-256 `9d7e0638d8e01ee49ae57dde3bb71e1928767265bd33b67a4dd4abc62b7345d6`.

They agree on the relevant topology: root `raspberrypi,4-model-b` / `brcm,bcm2711`; `/aliases/bluetooth` points to `/soc/serial@7e215040/bluetooth`; AUX UART is `okay`, clock cells `<0x11 0>`, pinctrl `<0xb6>`. That pin group selects GPIOs 32,33,30,31 with function 2 (alt5), matching the saved live pinmux log. The child is `okay`, `brcm,bcm43438-bt`, `max-speed=<230400>`, and `shutdown-gpios=<0xb 0 0>`. `skip-init` is on the **UART parent**, not the Bluetooth child. It is not consumed by the exact AUX driver. Its mere presence does not prove preserved UART state or explain this failure.

These are snapshots, not proof of today's firmware configuration. Their entire hashes differ; only the stated relevant properties were compared. The mainline 7.3 board DTS hash identifies the source reference, not the PFTF boot tree. The already-prepared PL011 overlay remains a separate untested routing experiment, not part of this patch.

## What the timeout actually proves

`build/upstream-pi/stable-4.5/kernel-reviewed/post-install-32.1.log` records `7.3.0-32.1-omarchy`, matching kernel/headers `7.3-32.1`, serial0/serial0-0 and hci0, then `0xfc18 tx timeout`, `BCM: failed to write update baudrate (-110)`, `Failed to set baudrate`, another `0xfc18` timeout and `BCM: Reset failed (-110)`. This establishes enumeration and initialization failure, not a working controller.

The source order corrects two conclusions in the ledger without editing it:

1. `bcm_open()` assigns the DT operational speed to `hu->oper_speed` for this compatible. Its data sets `drive_rts_on_open`, not `no_early_set_baudrate`.
2. `hci_uart_setup()` selects initial 115200, then calls the protocol's baud callback for 230400 **before** calling `bcm_setup()`.
3. `bcm_set_baudrate()` sends vendor opcode `0xfc18` synchronously; the six-byte parameters plus four-byte H4 header total **10 bytes**, not 15. The host remains at the initial rate while awaiting completion. The host changes baud only on success.
4. When that command fails, current serdev code logs and continues. Only then does `bcm_setup()` call `btbcm_initialize()`, whose first command is HCI Reset (`0x0c03`). The reset failure message does not show that an earlier reset succeeded; the repeated `0xfc18` timeout does not show a successful baud transition either. A queued command/timeout interaction needs a trace, not inference from those messages.

Therefore the saved log does not locate the fault after a host baud switch, establish an answering radio at 115200, prove a firmware download occurred, or exclude power/reset/flow-control problems. The saved 499999998 Hz AUX/VPU reading makes a gross static divisor error unlikely: approximate actual baud is 115313.7 for request 115200 and 230627.3 for request 230400. It is one clock snapshot, not proof that the clock remained stable through initialization. There is no basis for rewriting the AUX divisor or enabling a different firmware clock policy now.

## Candidate and source validation

The patch changes only the early serdev error branch: log, return `err`, and do not call protocol setup after a failed controller-speed command. Successful setup, speed selection and host baud switching retain their previous order. It applies to shared HCI serdev code, so upstream review must consider other UART protocols; it is not a Pi-only quirk.

The regression compiles the **entire actual extracted `hci_uart_setup()` function** as a small host C program, with interface stand-ins that record calls and inject callback outcomes. It does not model a UART, controller, firmware or timeout implementation. It verifies the real function returns `-110` and skips protocol setup/host operational switching after callback failure, and preserves success, zero operational speed, and initial/operational speed precedence. The same assertions fail on pristine 7.3 because it calls protocol setup and returns its result instead of the baud error. This guards error propagation, not hardware behavior.

Validation completed: patch applies with fuzz zero; pristine source negative control fails at the expected error-return assertion; patched source passes all cases. Full output: `/tmp/omarchy-pi-bluetooth-candidate-test.log`. No kernel was built, installed or loaded.

Parent validation command, from this workspace (the extracted source is available for this session):

```bash
python3 ../omarchy-pkgs-pi/tests/linux-bluetooth-baud.py /tmp/omarchy-bt-73-source/drivers/bluetooth/hci_serdev.c >/tmp/omarchy-pi-bluetooth-candidate-test.log 2>&1
cat /tmp/omarchy-pi-bluetooth-candidate-test.log
```

For another session, selectively extract `linux-7.3/drivers/bluetooth/hci_serdev.c` from the checksum-verified archive into a temporary directory and pass that path. The test enforces the pristine source hash and applies the candidate only in a temporary directory. Removing the two new sibling files reverses the candidate; the package recipe has not changed.

## Remaining parent gates

- Review the upstream error-propagation change across serdev protocols and decide whether to integrate it. It offers clearer failure semantics; controller function remains unresolved. Do not advertise a baud-transition fix.
- Obtain authorized physical-board access separately. Capture HCI command/completion and serial debug traces around power-on, the first `0xfc18`, and reset; confirm requested/actual host rate and RTS/CTS. Do not let both serdev and a userspace attach service own the UART. Do not interpret hci0 enumeration as success.
- Trace the actual shutdown GPIO provider and radio reset, pinmux and firmware selection. If evidence shows early vendor commands are unsupported, investigate a narrowly justified upstream compatible/board quirk that defers baud changes until initialization, following existing `no_early_set_baudrate` design. Do not set it globally for bcm43438/bcm4349 merely because those matches share data.
- Reconcile recipe lineage and capability/config checks, then build a matching candidate and headers with bounded resources in a later authorized task. Validate prepared-tree application, module ABI/payload, fresh install, upgrade and rollback. Keep existing candidate holds until the normal package channel is compatible.
- Prepare working encrypted-boot recovery and preserve prior packages/root/ESP/firmware before any install. For any future routing experiment, retain the mainline DMA overlay and console/recovery path; change one variable. Demonstrate rollback.
- Qualify actual controller initialization, scanning, pairing, reconnect, keyboard/mouse, applicable audio, Wi-Fi coexistence, cold/warm boot and suspend/resume. A fail-fast diagnostic candidate passing source tests satisfies none of those gates. Pi 5 and an actual 8GB Pi 4 remain outside this board's evidence.
