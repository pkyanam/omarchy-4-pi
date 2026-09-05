"""Pi 4 boot-clock trials. No voltage, GPU-clock, or thermal-trip overrides."""
import argparse
import contextlib
import difflib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

BEGIN = "# BEGIN OMARCHY PI CPU TRIAL"
END = "# END OMARCHY PI CPU TRIAL"
PROFILES = {"boost": None, "1800": 1800, "1900": 1900, "2000": 2000}
CONFLICT = re.compile(r"^(arm_freq(?:_min)?|arm_boost|gpu_freq(?:_min)?|core_freq\w*|h264_freq\w*|isp_freq\w*|v3d_freq\w*|hevc_freq\w*|sdram_freq\w*|over_voltage\w*|force_turbo|temp_limit|temp_soft_limit|dvfs)\s*=")


class Refused(RuntimeError):
  pass


def digest(data):
  return hashlib.sha256(data).hexdigest()


def atomic_write(path, data, mode=0o644):
  """Same-filesystem replacement; durable contents before publishing the name."""
  path = Path(path)
  fd, temporary = tempfile.mkstemp(prefix=".omarchy-", dir=path.parent)
  try:
    with os.fdopen(fd, "wb") as stream:
      os.fchmod(stream.fileno(), mode)
      stream.write(data)
      stream.flush()
      os.fsync(stream.fileno())
    os.replace(temporary, path)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
      os.fsync(directory)
    finally:
      os.close(directory)
  finally:
    if os.path.exists(temporary):
      os.unlink(temporary)


class Tuner:
  # Paths are injectable only through the Python test API, not privileged CLI
  # flags or environment variables. Production always uses the real system.
  def __init__(self, root=Path("/")):
    self.root = Path(root)
    self.state_dir = self.root / "var/lib/omarchy/pi-tune"
    self.receipt = self.state_dir / "state.json"
    self.baseline = self.state_dir / "config.original"

  def policies(self):
    return sorted((self.root / "sys/devices/system/cpu/cpufreq").glob("policy*"))

  def boot_id(self):
    return (self.root / "proc/sys/kernel/random/boot_id").read_text().strip()

  def uptime(self):
    return float((self.root / "proc/uptime").read_text().split()[0])

  def board(self):
    model = (self.root / "proc/device-tree/model").read_text().rstrip("\0\n")
    if not model.startswith("Raspberry Pi 4 Model B Rev "):
      raise Refused("Only Raspberry Pi 4 Model B is supported.")
    return model

  def config(self):
    candidates = [self.root / "boot/config.txt", self.root / "boot/firmware/config.txt"]
    found = [path for path in candidates if path.is_file()]
    if len(found) != 1 or found[0].is_symlink():
      raise Refused("Expected one regular boot config; ambiguous paths require manual review.")
    return found[0]

  def health(self, limit=70):
    temps, alarms = [], []
    for zone in (self.root / "sys/class/thermal").glob("thermal_zone*"):
      if (zone / "type").read_text().strip() == "cpu-thermal":
        temps.append(int((zone / "temp").read_text()) / 1000)
    for sensor in (self.root / "sys/class/hwmon").glob("hwmon*"):
      if (sensor / "name").read_text().strip() == "rpi_volt":
        alarms.append(int((sensor / "in0_lcrit_alarm").read_text()))
    if not temps or not alarms:
      raise Refused("Native CPU temperature and rpi_volt sensors are required; health is unknown.")
    if any(value != 0 for value in alarms):
      raise Refused("Undervoltage detected. Fix the power supply/cable before tuning.")
    if any(value < 0 or value >= limit for value in temps):
      raise Refused(f"CPU temperature must be below {limit}C.")
    return {"temperature_c": max(temps), "undervoltage_alarm": 0}

  def state(self):
    return json.loads(self.receipt.read_text()) if self.receipt.exists() else None

  def save(self, state):
    atomic_write(self.receipt, (json.dumps(state, indent=2) + "\n").encode())

  @contextlib.contextmanager
  def lock(self):
    self.state_dir.mkdir(parents=True, exist_ok=True)
    with (self.state_dir / "lock").open("a") as stream:
      fcntl.flock(stream, fcntl.LOCK_EX)
      yield

  def check_config(self, path, visited=None):
    """Conservatively inspect even conditionally inactive included settings."""
    visited = set() if visited is None else visited
    resolved = path.resolve()
    if resolved in visited or not resolved.is_relative_to(self.config().parent.resolve()):
      raise Refused("Cyclic or out-of-boot config include; review it manually.")
    visited.add(resolved)
    for raw in path.read_text().splitlines():
      line = raw.split("#", 1)[0].strip()
      if CONFLICT.match(line):
        raise Refused(f"Existing clock/voltage/thermal setting in {path.name}: {line}")
      if re.match(r"^include\s", line):
        include = line.split(maxsplit=1)[1].strip()
        if not include or " " in include or Path(include).is_absolute():
          raise Refused("Unsupported config include; review it manually.")
        self.check_config(path.parent / include, visited)
      if BEGIN in raw or END in raw:
        raise Refused("An existing managed block needs restoration before another trial.")
    visited.remove(resolved)

  def proposed(self, profile):
    self.board()
    state = self.state()
    if state and state["status"] != "restored":
      raise Refused("A profile is already managed. Restore it before starting another trial.")
    config = self.config()
    self.check_config(config)
    original = config.read_bytes()
    block = f"\n{BEGIN}\n[pi4]\narm_boost=1\n"
    if PROFILES[profile] is not None:
      block += f"arm_freq={PROFILES[profile]}\n"
    block += f"[all]\n{END}\n"
    return original, original.rstrip(b"\n") + b"\n" + block.encode()

  def preview(self, profile):
    before, after = self.proposed(profile)
    return "".join(difflib.unified_diff(before.decode().splitlines(True), after.decode().splitlines(True), fromfile="config.txt (current)", tofile=f"config.txt ({profile})"))

  def stage(self, profile):
    # Caller holds the lock and obtains explicit consent first. Recheck after
    # consent so stale previews cannot silently overwrite a changed config.
    original, proposed = self.proposed(profile)
    health = self.health()
    policies = self.policies()
    if not policies:
      raise Refused("CPUFreq policies are unavailable; cannot provide a runtime safety cap.")
    caps = {policy.name: int((policy / "scaling_max_freq").read_text()) for policy in policies}
    if any(value <= 0 for value in caps.values()):
      raise Refused("Invalid CPUFreq ceiling.")
    config = self.config()
    recovery = config.with_name("config.txt.omarchy-before-tune")
    # Preserve the last recovery file rather than overwrite a user's file.
    if recovery.exists() and recovery.read_bytes() != original:
      raise Refused(f"Recovery copy already differs: {recovery}; archive it manually first.")
    atomic_write(self.baseline, original)
    atomic_write(recovery, original)
    state = {"schema": 1, "status": "pending", "profile": profile,
      "config": str(config), "original_sha256": digest(original),
      "applied_sha256": digest(proposed), "staged_boot_id": self.boot_id(),
      "baseline_caps_khz": caps, "baseline_health": health}
    # A crash between receipt and boot-config replacement is recoverable.
    self.save(state)
    atomic_write(config, proposed)
    return state

  def cap(self, state):
    if not self.policies():
      raise Refused("CPUFreq policies disappeared.")
    for policy in self.policies():
      old = state["baseline_caps_khz"].get(policy.name)
      if old is None:
        raise Refused("CPUFreq policies changed; cannot select a verified baseline cap.")
      current = int((policy / "scaling_max_freq").read_text())
      ceiling = min(old, current)
      minimum = policy / "scaling_min_freq"
      if minimum.exists() and int(minimum.read_text()) > ceiling:
        minimum.write_text(str(ceiling))
      (policy / "scaling_max_freq").write_text(str(ceiling))

  def restore(self, reason="User requested restoration"):
    state = self.state()
    if not state or state["status"] == "restored":
      return "No managed clock profile to restore."
    # Cap even when later config edits prevent a safe file restoration.
    cap_error = None
    try:
      self.cap(state)
    except (Refused, OSError, ValueError) as error:
      cap_error = str(error)
    config = self.config()
    original = self.baseline.read_bytes()
    if str(config) != state["config"] or digest(original) != state["original_sha256"]:
      raise Refused("Recovery path or backup changed; use the boot-partition recovery copy.")
    if digest(config.read_bytes()) not in (state["original_sha256"], state["applied_sha256"]):
      raise Refused(f"Boot config changed after tuning; refusing to overwrite later edits. Runtime cap: {cap_error or 'applied'}. Remove the managed CPU trial block manually and reboot.")
    atomic_write(config, original)
    state.update(status="restored", reason=reason)
    self.save(state)
    if cap_error:
      return f"Original boot config restored, but runtime CPU cap failed ({cap_error}). Reboot now to restore firmware clocks."
    return "Original boot config restored; CPU ceiling capped. Reboot to restore firmware clock policy."

  def confirm(self):
    state = self.state()
    if not state or state["status"] != "pending":
      raise Refused("No pending trial.")
    if self.boot_id() == state["staged_boot_id"]:
      raise Refused("Reboot into the trial before confirming.")
    if self.uptime() >= 600:
      raise Refused("Confirmation window expired; restore the profile.")
    self.health()
    if digest(self.config().read_bytes()) != state["applied_sha256"]:
      raise Refused("Boot config changed after staging.")
    expected = (PROFILES[state["profile"]] or 1800) * 1000
    if not self.policies() or any(int((p / "cpuinfo_max_freq").read_text()) < expected for p in self.policies()):
      raise Refused("Kernel does not expose the requested clock. Do not assume the firmware setting worked; restore it.")
    state.update(status="confirmed", confirmed_boot_id=self.boot_id())
    self.save(state)

  def guard_step(self):
    state = self.state()
    if not state or state["status"] == "restored":
      return False
    if self.boot_id() == state["staged_boot_id"]:
      return False
    try:
      self.health(limit=75)
      if state["status"] == "pending" and self.uptime() >= 600:
        raise Refused("Trial not confirmed within ten minutes of boot.")
    except (Refused, OSError, ValueError) as error:
      print(self.restore(str(error)), flush=True)
      return False
    return True


def main():
  parser = argparse.ArgumentParser(description="Guarded Pi 4 CPU profiles; never changes voltage or thermal limits.")
  parser.add_argument("action", nargs="?", default="status", choices=["status", "preview", "apply", "confirm", "restore", "guard"])
  parser.add_argument("profile", nargs="?", choices=PROFILES)
  args = parser.parse_args()
  tuner = Tuner()
  if args.action in ("preview", "apply") and args.profile is None:
    parser.error("preview/apply requires a profile")
  if args.action not in ("preview", "apply") and args.profile is not None:
    parser.error("this action does not accept a profile")
  if args.action == "status":
    print(json.dumps({"board": tuner.board(), "managed": tuner.state()}, indent=2))
  elif args.action == "preview":
    print(tuner.preview(args.profile))
  else:
    if os.geteuid() != 0:
      raise Refused("This operation requires root through omarchy pi tune.")
    if args.action == "guard":
      while True:
        with tuner.lock():
          if not tuner.guard_step():
            break
        time.sleep(15)
    else:
      with tuner.lock():
        if args.action == "apply":
          print(tuner.preview(args.profile))
          tuner.health()
          print("Experimental: unstable clocks can prevent boot or corrupt storage. No clock is guaranteed safe.\nUse cooling and a reliable PSU. Back up the SD card and keep a card reader available.\nRecovery: restore config.txt.omarchy-before-tune as config.txt on the boot partition.\nAfter reboot, run 'omarchy pi tune confirm' within 10 minutes. Health checks are not a stability certification.")
          if not sys.stdin.isatty() or input("Type APPLY to confirm your backup, cooling, and recovery readiness: ") != "APPLY":
            raise Refused("No explicit interactive confirmation; nothing changed.")
          # Do not apply if the installed guard cannot be enabled. No immediate
          # reboot or service start: the profile only takes effect after reboot.
          subprocess.run(["systemctl", "enable", "omarchy-pi-tune-guard.service"], check=True)
          tuner.stage(args.profile)
          print("Trial staged. Reboot when ready; confirm within 10 minutes after boot.")
        elif args.action == "confirm":
          subprocess.run(["systemctl", "is-active", "--quiet", "omarchy-pi-tune-guard.service"], check=True)
          tuner.confirm()
          print("Profile confirmed. Health guard remains active; benchmark before claiming stability or speed.")
        else:
          print(tuner.restore())


if __name__ == "__main__":
  try:
    main()
  except (Refused, OSError, ValueError, subprocess.CalledProcessError) as error:
    print(f"Pi tuning refused: {error}", file=sys.stderr)
    sys.exit(1)
