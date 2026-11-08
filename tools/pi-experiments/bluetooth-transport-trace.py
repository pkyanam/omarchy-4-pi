#!/usr/bin/python3
"""Parent-reviewed, call-only exact7.3-32.1 diagnostic. No scalar ABI guesses."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time
import uuid


KERNEL = "7.3.0-32.1-omarchy"
TRACE = Path("/sys/kernel/tracing")
DRIVER = Path("/sys/bus/serial/drivers/hci_uart_bcm")
DEVICE = Path("/sys/bus/serial/devices/serial0-0")
WINDOW = 12
MAX_TRACE = 2 * 1024 * 1024
# Exact names only. No wildcard expansion, graph tracing, per-byte serial calls,
# generic 8250 IRQ paths, function arguments, pointers, payloads or registers.
REQUIRED = {"bcm_gpio_set_power": "hci_uart", "bcm_open": "hci_uart",
            "bcm_serdev_probe": "hci_uart", "bcm_recv": "hci_uart"}
OPTIONAL = {
  "hci_uart_set_baudrate": "hci_uart", "hci_uart_set_flow_control": "hci_uart",
  "bcm_set_baudrate": "hci_uart", "bcm_enqueue": "hci_uart",
  "hci_uart_write_work": "hci_uart", "hci_uart_receive_buf": "hci_uart",
  "ttyport_write_buf": None, "ttyport_receive_buf": None,
  "ttyport_write_wakeup": None, "ttyport_set_baudrate": None,
  "ttyport_set_flow_control": None, "ttyport_set_tiocm": None,
  "uart_set_termios": None,
}
DISCOVER = set(REQUIRED) | set(OPTIONAL) | {
  "serial8250_rx_chars", "serial8250_tx_chars", "serial8250_start_tx",
  "serial8250_modem_status",
}


def read(path, cap=256 * 1024):
  with Path(path).open("rb") as stream:
    data = stream.read(cap + 1)
  if len(data) > cap:
    raise RuntimeError(f"State exceeds cap: {path}")
  return data.decode("utf-8", errors="strict")


def write(path, value):
  with Path(path).open("w") as stream:
    stream.write(value + "\n")


def bound_copy(source, target, cap):
  with Path(source).open("rb") as src, Path(target).open("xb") as dst:
    remaining = cap
    while remaining:
      chunk = src.read(min(65536, remaining))
      if not chunk:
        return False
      dst.write(chunk)
      remaining -= len(chunk)
    return bool(src.read(1))


def symbols(path):
  found = {}
  with Path(path).open() as stream:
    for line in stream:
      fields = line.split()
      if fields and fields[0] in DISCOVER:
        found.setdefault(fields[0], []).append(fields[1] if len(fields) > 1 else None)
  return found


def select(found):
  selected = []
  for name, module in (REQUIRED | OPTIONAL).items():
    expected = f"[{module}]" if module else None
    matches = found.get(name, [])
    if matches == [expected]:
      selected.append(f"{name}:mod:{module}" if module else name)
    elif name in REQUIRED:
      raise RuntimeError(f"Required symbol missing/ambiguous: {name}: {matches}")
  return selected


def binding():
  link = DEVICE / "driver"
  return str(link.resolve(strict=True)) if link.is_symlink() else None


def snapshot():
  result = {"kernel": platform.release(), "machine": platform.machine(),
            "binding": binding(), "taint": read("/proc/sys/kernel/tainted").strip(),
            "instances": sorted(p.name for p in (TRACE / "instances").iterdir())}
  for name in ("current_tracer", "tracing_on", "trace_clock", "trace_options",
               "set_ftrace_filter", "set_ftrace_notrace", "events/enable",
               "kprobe_events", "dynamic_events"):
    path = TRACE / name
    result[name] = read(path) if path.exists() else None
  return result


def validate(state):
  if state["kernel"] != KERNEL or state["machine"] != "aarch64":
    raise RuntimeError("Requires the parent's exact installed aarch64 kernel")
  if state["taint"] != "0" or state["binding"] != str(DRIVER):
    raise RuntimeError("Unexpected taint or driver binding")
  if state["current_tracer"].strip() != "nop" or state["events/enable"].strip() != "0":
    raise RuntimeError("Global tracing/events already in use")
  if state["instances"] or any((state.get(k) or "").strip()
                               for k in ("kprobe_events", "dynamic_events")):
    raise RuntimeError("Existing instance or dynamic probe: abort without touching it")
  if os.cpu_count() != 4:
    raise RuntimeError("Expected four CPUs; review memory bound for this machine")
  if not any(line.split()[4] == "/sys/kernel/tracing" and
             " - tracefs " in line for line in read("/proc/self/mountinfo").splitlines()):
    raise RuntimeError("Expected tracefs mount at /sys/kernel/tracing")


class Capture:
  def __init__(self, output):
    self.output = output
    self.instance = TRACE / "instances" / ("omarchy_bt_" + uuid.uuid4().hex)
    self.created = False
    self.unbind_attempted = False
    self.child = None
    self.actions = []
    self.errors = []

  def save(self, name, value):
    (self.output / name).write_text(json.dumps(value, indent=2) + "\n")

  def action(self, name):
    self.actions.append({"action": name, "monotonic": time.monotonic()})
    self.save("actions.json", self.actions)

  def sysfs(self, operation, seconds):
    # Separate process bounds the parent's wait on a potentially blocking sysfs
    # driver callback. SIGKILL cannot guarantee killing an uninterruptible task.
    if self.child is not None:
      raise RuntimeError("Prior sysfs worker has not settled")
    self.action(operation + "-attempt")
    if operation == "unbind":
      self.unbind_attempted = True
    code = "import os,sys; f=os.open(sys.argv[1],os.O_WRONLY); os.write(f,b'serial0-0\\n'); os.close(f)"
    self.child = subprocess.Popen([sys.executable, "-I", "-c", code,
                                   str(DRIVER / operation)], stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  close_fds=True)
    try:
      rc = self.child.wait(timeout=seconds)
    except subprocess.TimeoutExpired as exc:
      raise RuntimeError(f"{operation} worker exceeded {seconds:.2f}s") from exc
    self.child = None
    self.action(operation + f"-result-{rc}")
    if rc:
      raise RuntimeError(f"{operation} failed (exit {rc})")

  def stop_child(self):
    if self.child is not None:
      self.child.kill()
      try:
        self.child.wait(timeout=1)
        self.child = None
      except subprocess.TimeoutExpired:
        self.errors.append("Uninterruptible sysfs worker remains; do not race it with another bind")

  def cleanup(self):
    # Each cleanup step is independent: failure to stop/read tracing must not
    # bypass binding recovery. Never recursively remove a tracefs directory.
    if self.created:
      try:
        write(self.instance / "tracing_on", "0")
      except OSError as exc:
        self.errors.append(f"Stop owned tracing: {exc}")
    self.stop_child()
    try:
      current = binding()
      if self.unbind_attempted and current is None and self.child is None:
        self.sysfs("bind", 4)
      elif current != str(DRIVER):
        self.errors.append(f"Unexpected binding {current}; no foreign binding touched")
    except (OSError, RuntimeError) as exc:
      self.errors.append(f"Restore binding: {exc}")
    self.stop_child()
    if self.created:
      try:
        truncated = bound_copy(self.instance / "trace", self.output / "trace.txt", MAX_TRACE)
        self.save("capture.json", {"truncated": truncated, "mode": "function-call-only"})
        for cpu in range(4):
          path = self.instance / "per_cpu" / f"cpu{cpu}" / "stats"
          (self.output / f"cpu{cpu}-stats.txt").write_text(read(path, 8192))
      except (OSError, RuntimeError) as exc:
        self.errors.append(f"Save owned trace: {exc}")
      try:
        write(self.instance / "current_tracer", "nop")
        self.instance.rmdir()
        self.created = False
      except OSError as exc:
        self.errors.append(f"Remove owned instance {self.instance}: {exc}")
    # No probe was created, so no global kprobe/dynamic-event write is allowed.
    return self.errors

  def run(self, selected):
    self.instance.mkdir()
    self.created = True
    self.save("owned.json", {"instance": str(self.instance), "events": [],
                             "original_binding": str(DRIVER)})
    write(self.instance / "tracing_on", "0")
    write(self.instance / "buffer_size_kb", "128")
    write(self.instance / "options/overwrite", "0")
    # These are TOP_LEVEL_TRACE_FLAGS in exact 7.3 and have no instance
    # controls. Preserve global record-cmd/record-tgid rather than attempting
    # to create absent tracefs entries or changing shared tracing policy.
    write(self.instance / "trace_clock", "mono")
    for option in ("stacktrace", "userstacktrace", "sym-addr", "branch",
                   "function-fork", "event-fork", "func_stack_trace"):
      path = self.instance / "options" / option
      if path.exists():
        write(path, "0")
    write(self.instance / "set_ftrace_filter", "\n".join(selected))
    actual = read(self.instance / "set_ftrace_filter")
    self.save("filter.json", {"requested": selected, "actual": actual})
    # A rejected/empty filter must never turn into unrestricted tracing.
    actual_names = {line.split()[0] for line in actual.splitlines() if line and not line.startswith("#")}
    wanted = {item.split(":")[0] for item in selected}
    if actual_names != wanted:
      raise RuntimeError("Kernel did not install the exact requested function filter")
    write(self.instance / "current_tracer", "function")
    if read(self.instance / "current_tracer").strip() != "function":
      raise RuntimeError("Instance function tracer unsupported")
    if binding() != str(DRIVER):
      raise RuntimeError("Binding changed during setup")
    self.save("instance.json", {"clock": read(self.instance / "trace_clock"),
                                "options": read(self.instance / "trace_options"),
                                "buffer_kib_total": read(self.instance / "buffer_total_size_kb")})
    start = time.monotonic()
    deadline = start + WINDOW
    self.action("trace-start")
    write(self.instance / "tracing_on", "1")
    self.sysfs("unbind", min(2, max(0.01, deadline - time.monotonic())))
    if binding() is not None:
      raise RuntimeError("Unbind did not detach expected device")
    self.sysfs("bind", min(8, max(0.01, deadline - time.monotonic())))
    if binding() != str(DRIVER):
      raise RuntimeError("Bind did not restore expected device")
    time.sleep(max(0, deadline - time.monotonic()))
    write(self.instance / "tracing_on", "0")
    self.action("trace-stop")


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--execute", action="store_true", help="Root-only, one coordinated rebind")
  parser.add_argument("--output", type=Path, help="New output directory; required for execution")
  args = parser.parse_args()
  plan = {"mode": "function-call-only", "window_seconds": WINDOW,
          "kernel": KERNEL, "device": str(DEVICE), "driver": str(DRIVER),
          "required": REQUIRED, "optional": OPTIONAL,
          "buffer_kib_per_cpu": 128, "trace_file_cap_bytes": MAX_TRACE,
          "scalar_probes": [], "execute": args.execute,
          "limits": "No acceptance/results/CTS/RX error counts/physical TX or RX proof. No global 8250 tracing."}
  if not args.execute:
    print(json.dumps(plan, indent=2))
    return 0
  if not args.output or os.geteuid() != 0:
    parser.error("--execute requires root and --output NEW_DIRECTORY")
  # A fixed root-owned lock serializes this helper, not other tracing tools.
  fd = os.open("/run/lock/omarchy-bt-transport.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
  with os.fdopen(fd, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    state = snapshot()
    validate(state)
    found = symbols(TRACE / "available_filter_functions")
    selected = select(found)
    args.output.mkdir(mode=0o700, parents=False, exist_ok=False)
    capture = Capture(args.output)
    capture.save("plan.json", plan)
    capture.save("before.json", state)
    capture.save("symbols.json", found)
    capture.save("selection.json", selected)
    old_handlers = {}

    def interrupted(signum, frame):
      raise RuntimeError(f"Interrupted by signal {signum}")

    failure = None
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
      old_handlers[sig] = signal.signal(sig, interrupted)
    try:
      # Fail if another actor changed shared tracing policy after preflight.
      if snapshot() != state:
        raise RuntimeError("Shared state changed during preflight")
      capture.run(selected)
    except (OSError, RuntimeError) as exc:
      failure = str(exc)
    finally:
      # Prevent a second normal termination signal from skipping restoration.
      for sig in old_handlers:
        signal.signal(sig, signal.SIG_IGN)
      errors = capture.cleanup()
      try:
        after = snapshot()
        capture.save("after.json", after)
        if after != state:
          errors.append("Post-state differs from recorded pre-state; parent review required")
      except (OSError, RuntimeError) as exc:
        errors.append(f"Post-state: {exc}")
      capture.save("result.json", {"failure": failure, "cleanup_errors": errors,
                                  "physical_evidence": False})
      for sig, handler in old_handlers.items():
        signal.signal(sig, handler)
    print(json.dumps({"output": str(args.output), "failure": failure, "cleanup_errors": errors}))
    return 1 if failure or errors else 0


if __name__ == "__main__":
  try:
    sys.exit(main())
  except (OSError, RuntimeError) as exc:
    print(f"Refused/failed: {exc}", file=sys.stderr)
    sys.exit(1)
