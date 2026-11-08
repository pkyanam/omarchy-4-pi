# Bluetooth UART progress candidate — 2026-11-08

Prepared `tools/pi-experiments/bluetooth-uart-progress.py` and adjacent offline tests. The default prints an offline plan. No Pi, SSH, probe registration, rebind, GPU work, benchmark, Docker invocation, install, kernel build, shared recipe edit, staging, commit, push, PR, subagent or external message (including Kai) occurred in this lane. Existing raw/call/scalar evidence and source helpers were preserved unchanged. Implementation used the supplied Sol/High harness; no provider/model substitution was made.

## Prior result and remaining gate

The parent reports one completed 12-second scalar rebind: 18 retained events, zero dropped events/kprobe misses, exact shared state/binding restoration and taint 0. Host baud requested/reported 115200; write requests/acceptance 10/10 and 4/4; no tty/Broadcom RX callbacks. Power 0/1 returned 0 after approximately 114–121 ms, with flow 0/RTS clear mask 4, power 1, flow 1/RTS set mask 4. These are software observations, not electrical measurements. The corrected raw `os.open`/`os.write` command writer is inherited unchanged.

**Current narrow gate: current-boot line identity is not yet proven here.** The saved `bt-scalar-trace-candidate/parent-scalar-post.log` maps `serial0-0` to `/sys/devices/platform/soc/fe215040.serial/fe215040.serial:0/fe215040.serial:0.0/serial0/serial0-0`; `/sys/class/tty/ttyS1` is absent under serdev. Neither that absence nor `serial0` proves `uart_port.line == 1`. Prior boot evidence naming ttyS1 must be checked against the current boot and exact controller before using it. This helper refuses live modes without a parent-reviewed identity attestation; it does not generate one or infer a line.

Parent identity JSON must contain `device_path` equal to the full path above, integer `line` in 1–255, current `boot_id`, `source_evidence_sha256` of the retained current-boot registration evidence, and `proof` equal to `current-boot UART registration maps fe215040.serial to ttyS<N>` with N replaced by the proven line. This is a trusted parent attestation, not automatic verification of the source log: inspect the actual registration evidence and hash it first. Retain the original log privately; do not export hardware addresses through this tracer. The helper independently compares the current boot ID and resolved serial device path before install and before rebind. Line zero is deliberately unsupported because failed numeric dereferences can yield zero. If the actual line is zero or the mapping cannot be established, stop; do not loosen the filter or invent evidence.

## Exact source and running BTF

Ignored evidence root: `build/upstream-pi/stable-4.5/bt-uart-progress-candidate/`. `source-manifest.json` records the extracted exact 7.3 source, inherited recipe/config/patch hashes and reviewed-path patch check. The actual archive SHA-256 was independently checked: `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`, matching the existing 7.3/32.1 manifest. No supplied recipe patch touches the reviewed source paths. No source was fetched from a moving branch.

The helper parses the captured raw little-endian BTF directly using Python's standard library; no compiler, dependency, container or installation is needed. The exact parent-captured BTF SHA-256 is `f8711335d174e735928d53a899d57e082b2b68f077333036c505ef887bd22959`. Live modes independently require `/sys/kernel/btf/vmlinux` with that same hash; they reject substitution of a saved BTF path. All member offsets are derived anew from that BTF and checked against source types and function signatures. `btf-layout.json` retains the derivation output, signatures, widths and generated fetch expressions. No numeric offset is embedded in the probe generator.

| RAM field in `uart_port` | BTF byte offset | Fetch width |
| --- | --- | --- |
| `line` | 340 | unsigned 32 |
| `hw_stopped` | 308 | unsigned 8 (`_Bool`) |
| `icount.cts` | 240 | unsigned 32 |
| `icount.rx`, `icount.tx` | 256, 260 | unsigned 32 |
| `icount.frame`, `icount.overrun`, `icount.parity` | 264, 268, 272 | unsigned 32 |
| `icount.brk`, `icount.buf_overrun` | 276, 280 | unsigned 32 |

`include/linux/serial_core.h:413` defines the counters as `__u32`; `:498` embeds `icount`; `:574` declares boolean `hw_stopped`; `:581` declares unsigned `line`. Exact BTF confirms `uart_8250_port.port` is a leading, embedded `uart_port` at offset zero. The parser refuses bitfields, unaligned, signed, partial-width and non-integer leaf fields. It verifies each selected function's exact argument types and return type, resolving typedefs and qualifiers. Native arm64 first argument x0 and second argument x1 follow the already reviewed exact-source register ABI. The only second-argument fetch is the CTS callback's low-byte boolean.

## Scope and meaning

Every probe is an entry probe, requires a unique exact built-in symbol, and records the RAM fields above. Every event has `line == N` installed and read back while disabled. Filters are checked again immediately before the inherited trace window. No wildcard, offset probe, per-byte callback, graph tracer, raw pointer argument, pointer value, payload, I/O address, UART register, destructive read, return-address export option or direct register operation is added. Generic callbacks still incur probe/filter overhead on other ports; only the proven port's scalar records are retained. The kernel event format inherently contains probe metadata; this uses formatted text with address/offset output disabled, not raw binary export.

| Exact source symbol/signature | Observation boundary |
| --- | --- |
| `void serial8250_start_tx(struct uart_port *)` | Start request and current software CTS stop state; no transmission claim |
| `void serial8250_tx_chars(struct uart_8250_port *)` | Before TX loop; entry alone proves no progress |
| `void serial8250_stop_tx(struct uart_port *)` | Stop request; `hw_stopped` can distinguish software CTS stop |
| `u16 serial8250_rx_chars(struct uart_8250_port *, u16)` | Before batched RX processing; no LSR argument is fetched |
| `unsigned int serial8250_modem_status(struct uart_8250_port *)` | After RX processing on the normal IRQ path, before the driver's existing MSR read; return/status is not fetched |
| `void uart_write_wakeup(struct uart_port *)` | May follow TX loop with updated counter, or CTS resume; evaluate ordering and deltas |
| `void uart_handle_cts_change(struct uart_port *, bool)` | CTS callback's active flag plus old software stop/counter state |

`drivers/tty/serial/8250/8250_port.c` contains these callbacks and the RX → modem → TX IRQ order. `serial8250_read_char()` increments RX and error counters, but is deliberately not probed. `include/linux/serial_core.h:879` increments `icount.tx` as bytes leave the software FIFO, before the TX loop's `serial_out()`. Therefore counter progress is driver queue progress consistent with the normal write path, not proof of a bus write completing, FIFO drain, shift-register activity or electrical TX. `uart_write_wakeup()` follows the normal loop but also serves other paths; use deltas and source-supported ordering, not event names alone. The x_char early-return path can lack this post-loop sample.

`drivers/tty/serial/serial_core.c:3471` increments `icount.cts`, then for software CTS changes sets `hw_stopped` before calling stop/start. The CTS entry sample is before that update; a subsequent stop/start sample can expose the new state. No callback means no observed transition, not measured CTS voltage. `uart_write_wakeup()` documents that the caller should hold the port lock; 8250 start/TX/stop and modem paths operate with that lock, and the CTS callback requires it. Callback arguments point to live driver RAM; only the validated embedded scalar fields are dereferenced. No pointer chasing into `membase`, device, tty, state, FIFO or operations tables occurs. Individual counter samples are not a new locking transaction or guaranteed coherent cross-callback snapshot. Existing kernel no-fault fetch behavior handles invalid memory; failed numeric fetches can appear zero and cannot support zero-counter conclusions.

Positive RX/error deltas locate driver receive/error processing even without tty RX delivery. Absence of samples, missing baseline/final sample, counter resets, unknown ownership changes, fetch faults, or overflow prevents a zero-progress conclusion. Counters are cumulative unsigned 32-bit values: evaluate modular differences only within the same proven port lifetime; do not subtract across close/reinitialization. Error counters classify driver observations, not valid HCI packets or a physical root cause. No correlated return probe is fabricated.

## Parent validation and one-window handoff

Keep the new helper adjacent to the existing scalar and transport helpers. Live mode pins their exact current hashes (`081de23982d893a200e0725de55a283631ae165ee87c0beb34206f7ed5db5b4a` and `1c1e9acc5ccd51b4ed8185f2239069ead398771478b77239edf42d9f20d694c1`); changed helpers require coordination/review, not an edit to those helpers from this lane. The inherited preflight, common exclusive lock, taint/kernel/binding/shared-policy checks, isolated 128 KiB-per-CPU non-overwrite buffer, UUID ownership journal, single-write command parser I/O, worker deadlines, signal cleanup, no normal-bind retry, conditional recovery, output caps, profile/stats and exact post-state comparison remain in effect. Ordinary signals enter cleanup; SIGKILL, uninterruptible callbacks or blocking control-file calls can defeat deadlines and cleanup.

Parent first reviews source/BTF evidence and establishes current-boot line evidence plus exclusive tracing and normal board health. Run disabled format validation **without rebinding** under the parent's existing root procedure, from the directory holding all three helpers:

```bash
python3 bluetooth-uart-progress.py --validate-probes --identity /var/tmp/bt-uart-identity.json --output /var/tmp/bt-uart-formats-01
```

Use fresh output paths. Review `result.json`, every `*-format.txt`, `uart-contract.json`, `filters.json`, `formats.json`, `before.json` and `after.json`. Require no failure, no cleanup errors, no rebind, no unresolved worker, and equal before/after state. Confirm all installed fields, widths and signedness, exact line filter, BTF hash and identity. The saved format hash covers normalized formats **plus** the entire UART contract (BTF layout/signatures, identity, filter and probe definitions), so line/boot/layout changes invalidate review. Missing symbols or rejected formats stop before any bind; never replace them with clones or numeric addresses.

Only after successful review, parent may run exactly one bounded 12-second trace:

```bash
reviewed_formats=$(python3 -c 'import json; print(json.load(open("/var/tmp/bt-uart-formats-01/formats.json"))["sha256"])')
python3 bluetooth-uart-progress.py --execute --identity /var/tmp/bt-uart-identity.json --expected-formats "$reviewed_formats" --output /var/tmp/bt-uart-trace-01
```

Recheck exact state/binding/taint, cleanup result, owned resources/workers, trace truncation, all CPU stats and probe profile before interpreting. Reject absence-based claims with dropped events, overruns, misses or truncation. No scans, pairing or concurrent tracers. Preserve all prior scalar/raw evidence.

## Offline validation and fallback

`tests-final.log`: five passing tests exercise changed-BTF refusal, actual captured-BTF scalar derivation and pointer-field rejection, missing/invalid line evidence and rejection of extra attestation data, live-mode identity gating and refusal to substitute a saved BTF during live mode. These checks do not emulate kernel probe registration or prove hardware behavior. `dry-run.json`, `btf-layout.json`, `source-manifest.json` and `deliverable-sha256.json` retain offline evidence. The initial BTF inspection correctly refused source typedef spelling `u16` where resolved BTF says `short unsigned int`; the verifier now compares resolved types consistently, including `_Bool`. No probe definition was physically tried.

If current-boot line correlation cannot be established, or exact symbols/formats cannot safely expose these boundaries, stop at that narrow blocker. Minimal matching-driver-context logging would record the port line, RAM TX/RX/error counters and `hw_stopped` under the existing port lock at entry/exit of the selected 8250 batch processing and CTS transition, with only scalar request/result context. This would supply correlated before/after counters without a global per-byte probe or pointer export. Integrate through the owning matching kernel recipe with a new release/matching headers and coordinated bounded build/install only after parent review; no logging patch, build or staging was made here. No UART register snapshot is proposed by this lane, and neither such logging nor this tracer can replace physical TX/RX/RTS/CTS measurements.

## Parent physical validation checkpoint

Parent established the missing current-boot identity directly from the kernel registration log: AUX controller maps to ttyS1. Disabled format/line-filter validation passed without rebind, and every field/filter was reviewed. A single guarded 12-second trace then completed with exact shared-state/binding restoration, taint zero, no truncation/drops/overruns or probe misses. Four samples show software hw_stopped returning to1 when flow control is re-enabled; no selected TX-loop, RX, CTS-change or wakeup call occurred. There is no final post-command counter sample, so zero sample counters cannot prove full-window zero progress. See [sanitized evidence](../results/pi4-4gb-native/2026-11-08/bluetooth-uart-progress/README.md).

A later pinctrl snapshot confirms UART ownership/alt5 mux but was after initialization failed; it is not active CTS evidence. The source/driver investigation continues independently with no Pi authority. This supersedes only the identity/not-run gates above; pin-level transmission and the actual root cause remain unproven.
