import importlib.util
from pathlib import Path
import tempfile
import unittest
import multiprocessing
import sys

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("pi_tune", ROOT / "default/pi/tune.py")
tune = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tune)
sys.path.insert(0, str(ROOT / "default/pi"))
import benchmark


class TuneTests(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.TemporaryDirectory()
    self.addCleanup(self.tmp.cleanup)
    self.root = Path(self.tmp.name)
    self.tuner = tune.Tuner(self.root)
    self.write("proc/device-tree/model", "Raspberry Pi 4 Model B Rev 1.5\0")
    self.write("proc/sys/kernel/random/boot_id", "before")
    self.write("proc/uptime", "30.0 10.0")
    self.write("boot/config.txt", "arm_64bit=1\n[all]\ndtoverlay=vc4-kms-v3d\n")
    self.write("sys/class/thermal/thermal_zone0/type", "cpu-thermal")
    self.write("sys/class/thermal/thermal_zone0/temp", "43800")
    self.write("sys/class/hwmon/hwmon0/name", "rpi_volt")
    self.write("sys/class/hwmon/hwmon0/in0_lcrit_alarm", "0")
    self.policy = "sys/devices/system/cpu/cpufreq/policy0/"
    self.write(self.policy + "scaling_max_freq", "1800000")
    self.write(self.policy + "cpuinfo_max_freq", "1800000")
    self.original = self.tuner.config().read_bytes()

  def write(self, name, value):
    path = self.root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value)
    return path

  def stage(self, profile="1900"):
    with self.tuner.lock():
      return self.tuner.stage(profile)

  def reboot(self):
    self.write("proc/sys/kernel/random/boot_id", "after")
    self.write(self.policy + "scaling_max_freq", "1900000")
    self.write(self.policy + "cpuinfo_max_freq", "1900000")

  def test_preview_does_not_write(self):
    for profile in tune.PROFILES:
      diff = self.tuner.preview(profile)
      self.assertIn("+arm_boost=1", diff)
      for forbidden in ("over_voltage", "force_turbo", "temp_limit", "gpu_freq", "dvfs"):
        self.assertNotIn(forbidden, diff)
    self.assertEqual(self.original, self.tuner.config().read_bytes())
    self.assertFalse(self.tuner.state_dir.exists())

  def test_conflicts_in_includes_rejected(self):
    for setting in ("arm_freq=1700", "force_turbo=1", "over_voltage=6", "temp_limit=85", "dvfs=2"):
      self.write("boot/config.txt", "include clocks.txt\n")
      self.write("boot/clocks.txt", "[none]\n" + setting)
      with self.assertRaises(tune.Refused):
        self.tuner.preview("2000")

  def test_cyclic_and_external_includes_refused(self):
    for content in ("include config.txt", "include ../outside.txt", "include /etc/passwd"):
      self.write("boot/config.txt", content)
      with self.assertRaises(tune.Refused):
        self.tuner.preview("boost")

  def test_ambiguous_or_symlink_config_refused(self):
    second = self.write("boot/firmware/config.txt", "")
    with self.assertRaises(tune.Refused):
      self.tuner.preview("boost")
    second.unlink()
    self.tuner.config().rename(self.root / "boot/real.txt")
    (self.root / "boot/config.txt").symlink_to("real.txt")
    with self.assertRaises(tune.Refused):
      self.tuner.preview("boost")

  def test_board_gate(self):
    self.write("proc/device-tree/model", "Raspberry Pi 5 Model B Rev 1.0")
    with self.assertRaises(tune.Refused):
      self.stage()

  def test_hot_and_undervolted_refused_before_boot_mutation(self):
    self.write("sys/class/thermal/thermal_zone0/temp", "70000")
    with self.assertRaises(tune.Refused):
      self.stage()
    self.write("sys/class/thermal/thermal_zone0/temp", "43000")
    self.write("sys/class/hwmon/hwmon0/in0_lcrit_alarm", "1")
    with self.assertRaises(tune.Refused):
      self.stage()
    self.assertEqual(self.original, self.tuner.config().read_bytes())
    self.assertIsNone(self.tuner.state())

  def test_unknown_sensor_refused(self):
    (self.root / "sys/class/hwmon/hwmon0/name").write_text("unrelated")
    with self.assertRaises(tune.Refused):
      self.stage()

  def test_backup_and_pending_receipt(self):
    state = self.stage()
    self.assertEqual(self.tuner.baseline.read_bytes(), self.original)
    self.assertEqual((self.root / "boot/config.txt.omarchy-before-tune").read_bytes(), self.original)
    self.assertEqual(state["status"], "pending")
    self.assertIn(b"arm_freq=1900", self.tuner.config().read_bytes())
    with self.assertRaises(tune.Refused):
      self.stage("2000")

  def test_existing_recovery_copy_not_overwritten(self):
    self.write("boot/config.txt.omarchy-before-tune", "precious")
    with self.assertRaises(tune.Refused):
      self.stage()
    self.assertEqual(self.original, self.tuner.config().read_bytes())

  def test_confirm_requires_reboot_and_exposed_clock(self):
    self.stage()
    with self.assertRaises(tune.Refused):
      self.tuner.confirm()
    self.reboot()
    self.write(self.policy + "cpuinfo_max_freq", "1800000")
    with self.assertRaises(tune.Refused):
      self.tuner.confirm()
    self.write(self.policy + "cpuinfo_max_freq", "1900000")
    self.tuner.confirm()
    self.assertEqual(self.tuner.state()["status"], "confirmed")

  def test_confirm_rejects_late_trial(self):
    self.stage()
    self.reboot()
    self.write("proc/uptime", "601 10")
    with self.assertRaises(tune.Refused):
      self.tuner.confirm()

  def test_no_guard_work_on_stock_or_before_reboot(self):
    self.assertFalse(self.tuner.guard_step())
    self.stage()
    self.assertFalse(self.tuner.guard_step())
    self.assertEqual(self.tuner.state()["status"], "pending")

  def test_timeout_restores_exact_bytes_and_caps_cpu(self):
    self.stage()
    self.reboot()
    self.assertTrue(self.tuner.guard_step())
    self.write("proc/uptime", "601 10")
    self.assertFalse(self.tuner.guard_step())
    self.assertEqual(self.original, self.tuner.config().read_bytes())
    self.assertEqual((self.root / (self.policy + "scaling_max_freq")).read_text(), "1800000")
    self.assertEqual(self.tuner.state()["status"], "restored")

  def test_confirmed_health_guard_remains_active(self):
    self.stage()
    self.reboot()
    self.tuner.confirm()
    self.write("proc/uptime", "3600 10")
    self.assertTrue(self.tuner.guard_step())
    self.write("sys/class/thermal/thermal_zone0/temp", "75000")
    self.assertFalse(self.tuner.guard_step())
    self.assertEqual(self.original, self.tuner.config().read_bytes())

  def test_power_fault_restores(self):
    self.stage()
    self.reboot()
    self.write("sys/class/hwmon/hwmon0/in0_lcrit_alarm", "1")
    self.assertFalse(self.tuner.guard_step())
    self.assertEqual(self.tuner.state()["status"], "restored")

  def test_later_user_edits_preserved_even_during_guard_failure(self):
    self.stage()
    self.reboot()
    content = self.tuner.config().read_bytes() + b"# newer display customization\n"
    self.tuner.config().write_bytes(content)
    with self.assertRaises(tune.Refused):
      self.tuner.restore()
    self.assertEqual(content, self.tuner.config().read_bytes())
    self.assertEqual((self.root / (self.policy + "scaling_max_freq")).read_text(), "1800000")

  def test_modified_backup_refused(self):
    self.stage()
    self.tuner.baseline.write_bytes(b"changed")
    with self.assertRaises(tune.Refused):
      self.tuner.restore()

  def test_restore_is_idempotent(self):
    self.stage()
    self.tuner.restore()
    self.tuner.restore()
    self.assertEqual(self.original, self.tuner.config().read_bytes())

  def test_recovery_survives_unavailable_runtime_cap(self):
    self.stage()
    (self.root / (self.policy + "scaling_max_freq")).unlink()
    message = self.tuner.restore()
    self.assertIn("runtime CPU cap failed", message)
    self.assertEqual(self.original, self.tuner.config().read_bytes())

  def test_runtime_cap_can_lower_an_incompatible_minimum(self):
    self.stage()
    self.reboot()
    self.write(self.policy + "scaling_min_freq", "1900000")
    self.tuner.restore()
    self.assertEqual((self.root / (self.policy + "scaling_min_freq")).read_text(), "1800000")

  def test_short_benchmark_cleans_up_workers(self):
    result = benchmark.run(0.5, 1, self.tuner)
    self.assertTrue(result["completed"])
    self.assertEqual(result["workload"], "sha256-1MiB-v1")
    self.assertGreater(result["processed_mib"], 0)
    self.assertFalse(multiprocessing.active_children())
    self.assertEqual(self.original, self.tuner.config().read_bytes())

  def test_benchmark_aborts_on_heat_and_reaps_workers(self):
    calls = 0
    def health(limit=70):
      nonlocal calls
      calls += 1
      if calls > 1:
        raise benchmark.Refused("Temperature reached stop threshold")
      return {"temperature_c": 43.8, "undervoltage_alarm": 0}
    self.tuner.health = health
    result = benchmark.run(0.5, 1, self.tuner)
    self.assertFalse(result["completed"])
    self.assertIn("Temperature", result["stop_reason"])
    self.assertFalse(multiprocessing.active_children())


if __name__ == "__main__":
  unittest.main(verbosity=2)
