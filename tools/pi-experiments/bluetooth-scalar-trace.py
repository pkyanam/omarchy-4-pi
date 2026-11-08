#!/usr/bin/python3
"""Exact 7.3 arm64 scalar probes; default is an offline plan, never a rebind."""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("bt_transport", Path(__file__).with_name("bluetooth-transport-trace.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

# Proven against the exact linux-7.3 source, not $argN or structure offsets.
# (event, kind, exact symbol, module, [(field, fetch, bytes, signed)])
PROBES = [
  ("write", "p", "ttyport_write_buf", None, [("requested", "%x2:u64", 8, 0)]),
  ("written", "r64", "ttyport_write_buf", None, [("accepted", "$retval:s64", 8, 1)]),
  ("baud", "p", "ttyport_set_baudrate", None, [("requested", "%x1:u32", 4, 0)]),
  ("baud_return", "r64", "ttyport_set_baudrate", None, [("reported", "$retval:u32", 4, 0)]),
  ("flow", "p", "ttyport_set_flow_control", None, [("enabled", "%x1:u8", 1, 0)]),
  ("tiocm", "p", "ttyport_set_tiocm", None, [("set", "%x1:u32", 4, 0), ("clear", "%x2:u32", 4, 0)]),
  ("tiocm_return", "r64", "ttyport_set_tiocm", None, [("result", "$retval:s32", 4, 1)]),
  ("power", "p", "bcm_gpio_set_power", "hci_uart", [("powered", "%x1:u8", 1, 0)]),
  ("power_return", "r64", "bcm_gpio_set_power", "hci_uart", [("result", "$retval:s32", 4, 1)]),
  ("rx", "p", "ttyport_receive_buf", None, [("count", "%x3:u64", 8, 0)]),
  ("bcm_rx", "p", "bcm_recv", "hci_uart", [("count", "%x2:s32", 4, 1)]),
]


@contextmanager
def atomic_signals():
  # Close ordinary-signal gaps between kernel side effects and ownership flags.
  previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM, signal.SIGHUP})
  try:
    yield
  finally:
    signal.pthread_sigmask(signal.SIG_SETMASK, previous)


def digest(value):
  return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def append_probe(command):
  # kprobe_events is a command parser, not a regular appendable file.
  # Python open("a") seeks to EOF; its seq_lseek rejects SEEK_END (EINVAL).
  # No O_TRUNC/O_CREAT, buffered stream, seek or retry of a partial command.
  payload = (command + "\n").encode("ascii")
  fd = os.open(base.TRACE / "kprobe_events", os.O_WRONLY | os.O_CLOEXEC)
  try:
    written = os.write(fd, payload)
    if written != len(payload):
      raise RuntimeError(f"Short kprobe command write: {written}/{len(payload)}; not retried")
  finally:
    os.close(fd)


def definitions():
  result = {}
  for line in base.read(base.TRACE / "kprobe_events").splitlines():
    parts = line.split()
    if parts and not line.startswith("#") and ":" in parts[0]:
      result[parts[0].split(":", 1)[1]] = " ".join(parts)
  return result


def check_format(text, fields):
  actual = {}
  for declaration, size, signed in re.findall(r"field:([^;]+);\s*offset:\d+;\s*size:(\d+);\s*signed:(\d+);", text):
    actual[declaration.split()[-1]] = (int(size), int(signed))
  expected = {name: (size, signed) for name, _, size, signed in fields}
  user = {k: v for k, v in actual.items() if not k.startswith("common_") and k not in {"__probe_ip", "__probe_func", "__probe_ret_ip"}}
  if user != expected:
    raise RuntimeError(f"Unexpected installed scalar format: {user}, expected {expected}")
  # IDs and group/name vary per installation; all other format text is reviewed.
  return re.sub(r"(?m)^(name:|ID:).*$", "", text)


def shared_state(capture=None):
  state = base.snapshot()
  # Include global option state that base.snapshot already covers, and debug policy.
  debug = Path("/sys/kernel/debug/dynamic_debug/control")
  state["dynamic_debug"] = base.read(debug, 4 * 1024 * 1024) if debug.exists() else None
  state["buffer_size_kb"] = base.read(base.TRACE / "buffer_size_kb")
  if capture:
    state["instances"] = [n for n in state["instances"] if n != capture.instance.name]
    for key in ("kprobe_events", "dynamic_events"):
      if state.get(key) is not None:
        state[key] = "".join(line + "\n" for line in state[key].splitlines()
                             if not (len(line.split()) and line.split()[0].split(":", 1)[-1].startswith(capture.group + "/")))
  return state


class Capture(base.Capture):
  def __init__(self, output):
    super().__init__(output)
    self.group = "omarchy_bts_" + uuid.uuid4().hex
    self.pending = []
    self.installed = {}
    self.commands = {}
    self.formats = {}
    self.bind_attempted = False

  def sysfs(self, operation, seconds):
    if self.child is not None:
      raise RuntimeError("Prior sysfs worker has not settled")
    self.action(operation + "-attempt")
    code = "import os,sys; f=os.open(sys.argv[1],os.O_WRONLY); os.write(f,b'serial0-0\\n'); os.close(f)"
    with atomic_signals():
      if operation == "unbind":
        self.unbind_attempted = True
      else:
        self.bind_attempted = True
      self.child = subprocess.Popen([sys.executable, "-I", "-c", code, str(base.DRIVER / operation)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
    self.save("worker.json", {"pid": self.child.pid, "operation": operation})
    try:
      rc = self.child.wait(timeout=seconds)
    except subprocess.TimeoutExpired as exc:
      raise RuntimeError(f"{operation} worker exceeded {seconds:.2f}s") from exc
    self.child = None
    self.action(operation + f"-result-{rc}")
    if rc:
      raise RuntimeError(f"{operation} failed (exit {rc})")

  def stop_child(self):
    try:
      super().stop_child()
    except OSError as exc:
      self.errors.append(f"Stop owned sysfs worker: {exc}; no competing bind")

  def install(self):
    found = base.symbols(base.TRACE / "available_filter_functions")
    self.save("symbols.json", found)
    for _, _, symbol, module, _ in PROBES:
      if found.get(symbol) != ([f"[{module}]"] if module else [None]):
        raise RuntimeError(f"Missing/ambiguous exact symbol: {symbol}")
    with atomic_signals():
      self.instance.mkdir()
      self.created = True
    self.save("owned.json", {"instance": str(self.instance), "events": []})
    base.write(self.instance / "tracing_on", "0")
    base.write(self.instance / "current_tracer", "nop")
    base.write(self.instance / "buffer_size_kb", "128")
    base.write(self.instance / "options/overwrite", "0")
    base.write(self.instance / "trace_clock", "mono")
    for option in ("stacktrace", "userstacktrace", "sym-addr", "sym-offset", "branch", "event-fork"):
      path = self.instance / "options" / option
      if path.exists():
        base.write(path, "0")
    for name, kind, symbol, module, fields in PROBES:
      key = self.group + "/" + name
      command = f"{kind}:{key} {module + ':' if module else ''}{symbol} " + " ".join(f"{field}={fetch}" for field, fetch, _, _ in fields)
      if key in definitions():
        raise RuntimeError("Unique probe name collision")
      # Journal before the syscall: signals/errors after kernel commit still clean up.
      self.commands[key] = command
      self.pending.append(key)
      self.save("owned.json", {"instance": str(self.instance), "events": self.pending})
      try:
        append_probe(command)
      except (OSError, RuntimeError) as exc:
        # Snapshot immediately, before cleanup; never clear shared error_log.
        diagnostic = {"command": command, "exception": str(exc),
                      "errno": getattr(exc, "errno", None)}
        try:
          diagnostic["tracefs_error_log"] = base.read(base.TRACE / "error_log")
        except (OSError, RuntimeError) as read_exc:
          diagnostic["error_log_read_failure"] = str(read_exc)
        self.save("registration-failure.json", diagnostic)
        raise
      self.installed[key] = definitions().get(key)
      if self.installed[key] is None:
        raise RuntimeError(f"Probe installation not visible: {key}")
      event = self.instance / "events" / self.group / name
      text = base.read(event / "format")
      self.formats[name] = check_format(text, fields)
      (self.output / (name + "-format.txt")).write_text(text)
    self.save("formats.json", {"sha256": digest(self.formats), "normalized": self.formats})
    self.save("instance.json", {"options": base.read(self.instance / "trace_options"), "clock": base.read(self.instance / "trace_clock")})

  def run_window(self, before):
    for name, *_ in PROBES:
      base.write(self.instance / "events" / self.group / name / "enable", "1")
    if shared_state(self) != before or definitions() != self.installed:
      raise RuntimeError("Shared state/probes changed before rebind")
    if base.binding() != str(base.DRIVER):
      raise RuntimeError("Binding changed before rebind")
    deadline = time.monotonic() + base.WINDOW
    self.action("trace-start")
    base.write(self.instance / "tracing_on", "1")
    self.sysfs("unbind", 2)
    if base.binding() is not None:
      raise RuntimeError("Unbind did not detach device")
    remaining = deadline - time.monotonic()
    if remaining <= 0:
      raise RuntimeError("Window exhausted before bind")
    self.sysfs("bind", min(8, remaining))
    if base.binding() != str(base.DRIVER):
      raise RuntimeError("Bind did not restore device")
    time.sleep(max(0, deadline - time.monotonic()))
    base.write(self.instance / "tracing_on", "0")
    self.action("trace-stop")

  def cleanup(self):
    # Every step remains independent. No bind after an install-only failure.
    if self.created:
      try:
        base.write(self.instance / "tracing_on", "0")
      except OSError as exc:
        self.errors.append(f"Stop trace: {exc}")
    self.stop_child()
    try:
      current = base.binding()
      if self.unbind_attempted and current is None and self.child is None and not self.bind_attempted:
        self.sysfs("bind", 4)
      elif self.unbind_attempted and current != str(base.DRIVER):
        self.errors.append(f"Binding unresolved: {current}; no retry/racing bind")
    except (OSError, RuntimeError) as exc:
      self.errors.append(f"Binding recovery: {exc}")
    self.stop_child()
    if self.created:
      for name, *_ in PROBES:
        path = self.instance / "events" / self.group / name / "enable"
        try:
          if path.exists():
            base.write(path, "0")
        except OSError as exc:
          self.errors.append(f"Disable {name}: {exc}")
      try:
        truncated = base.bound_copy(self.instance / "trace", self.output / "trace.txt", base.MAX_TRACE)
        self.save("capture.json", {"truncated": truncated})
        for cpu in range(4):
          (self.output / f"cpu{cpu}-stats.txt").write_text(base.read(self.instance / "per_cpu" / f"cpu{cpu}" / "stats", 8192))
        (self.output / "kprobe-profile.txt").write_text(base.read(base.TRACE / "kprobe_profile"))
      except (OSError, RuntimeError) as exc:
        self.errors.append(f"Save trace/stats: {exc}")
      try:
        self.instance.rmdir()
        self.created = False
      except OSError as exc:
        self.errors.append(f"Remove owned instance: {exc}")
    for key in reversed(self.pending):
      try:
        actual = definitions().get(key)
        # A failed write can still have installed our UUID event. A changed
        # known definition belongs to a racing actor and must be left alone.
        if actual is not None:
          if actual != self.installed.get(key, self.commands[key]):
            raise RuntimeError("Owned definition changed; left untouched")
          append_probe("-:" + key)
      except (OSError, RuntimeError) as exc:
        self.errors.append(f"Remove {key}: {exc}")
    return self.errors


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  modes = parser.add_mutually_exclusive_group()
  modes.add_argument("--validate-probes", action="store_true", help="Install, save formats, remove; NO rebind")
  modes.add_argument("--execute", action="store_true", help="One 12-second rebind after format review")
  parser.add_argument("--expected-formats", help="SHA256 from reviewed validate-probes formats.json")
  parser.add_argument("--output", type=Path)
  args = parser.parse_args()
  plan = {"kernel": base.KERNEL, "window_seconds": base.WINDOW, "probes": PROBES,
          "fetches": "Scalar integer registers/returns only; no pointer arguments, dereferences or I/O", "execute": args.execute}
  if not (args.execute or args.validate_probes):
    print(json.dumps(plan, indent=2))
    return 0
  if os.geteuid() != 0 or not args.output:
    parser.error("Live modes require root and --output NEW_DIRECTORY")
  if args.execute and not re.fullmatch(r"[0-9a-f]{64}", args.expected_formats or ""):
    parser.error("--execute requires --expected-formats reviewed SHA256")
  fd = os.open("/run/lock/omarchy-bt-transport.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
  with os.fdopen(fd, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    before = shared_state()
    base.validate(before)
    args.output.mkdir(mode=0o700, exist_ok=False)
    cap = Capture(args.output)
    cap.save("before.json", before)
    cap.save("plan.json", plan)
    failure = None
    handlers = {}
    def interrupted(signum, frame):
      raise RuntimeError(f"Interrupted by signal {signum}")
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
      handlers[sig] = signal.signal(sig, interrupted)
    try:
      if shared_state() != before:
        raise RuntimeError("Shared state changed before setup")
      cap.install()
      if shared_state(cap) != before:
        raise RuntimeError("Foreign shared state changed during setup")
      if args.execute:
        if digest(cap.formats) != args.expected_formats:
          raise RuntimeError("Installed formats differ from parent-reviewed formats")
        cap.run_window(before)
    except (OSError, RuntimeError) as exc:
      failure = str(exc)
    finally:
      for sig in handlers:
        signal.signal(sig, signal.SIG_IGN)
      errors = cap.cleanup()
      try:
        after = shared_state()
        cap.save("after.json", after)
        if after != before:
          errors.append("Shared post-state differs; parent review required")
      except (OSError, RuntimeError) as exc:
        errors.append(f"Post-state: {exc}")
      cap.save("result.json", {"failure": failure, "cleanup_errors": errors, "rebind_attempted": cap.unbind_attempted, "physical_evidence": False, "unresolved_worker_pid": cap.child.pid if cap.child else None})
      for sig, handler in handlers.items():
        signal.signal(sig, handler)
    print(json.dumps({"output": str(args.output), "failure": failure, "cleanup_errors": errors}))
    return 1 if failure or errors else 0


if __name__ == "__main__":
  try:
    sys.exit(main())
  except (OSError, RuntimeError) as exc:
    print(f"Refused/failed: {exc}", file=sys.stderr)
    sys.exit(1)
