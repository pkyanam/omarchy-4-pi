# Bounded Bluetooth function-call trace

Parent executed one 12-second isolated trace and one unbind/bind of serial0-0. Exact selected callbacks, all 23 events (task names/PIDs omitted), per-CPU stats and restoration assertions are in observations.json. No truncation, overrun or dropped event was reported. Global tracing state and binding exactly matched before/after; taint remained zero. The owned instance was removed. Existing controller initialization failure remains.

The first attempt stopped before tracing or rebind because exact Linux 7.3 exposes record-cmd/record-tgid only at top level. Opening the absent instance controls for writing tried to create entries and returned EACCES. This was not an authorization rejection or a read-only per-instance control. Parent removed those writes, preserving shared flags. Ten control tests passed; the new unavailable-control regression fails against the original helper. Both attempts remain in ignored raw evidence.

Observed path: power/open/flow requests, initial tty baud setter, Broadcom baud command path, two enqueue and tty write-adapter entries, then two tty wakeups. Selected tty/Broadcom receive callbacks had no entries in this capture. This shows calls, not arguments, acceptance counts, successful FIFO transmission, electrical inactivity or a valid controller answer. No scalar ABI guesses or UART register reads were made. A separately reviewed scalar trace or matching source logging is still required.

Reproducer: tools/pi-experiments/bluetooth-transport-trace.py; dry-run default, explicit root --execute only. Detailed contract and recovery limits: plans/omarchy-pi-bluetooth-transport-trace.md. No firmware, device-tree, package or persistent debug policy changed.
