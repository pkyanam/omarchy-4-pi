#!/usr/bin/env python3
"""Parent-only explicit invocation; one child, wall deadline, no retry/recovery."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def main():
  p = argparse.ArgumentParser(description=__doc__)
  p.add_argument("--binary", required=True, type=Path)
  p.add_argument("--output", required=True, type=Path, help="new directory")
  mode = p.add_mutually_exclusive_group(required=True)
  mode.add_argument("--list", action="store_true")
  mode.add_argument("--device-uuid")
  p.add_argument("--shader", type=Path)
  args = p.parse_args()
  if os.geteuid() == 0:
    p.error("run as the normal desktop user; no privileged device access")
  if not args.list and (not args.shader or len(args.device_uuid) != 32 or any(c not in "0123456789abcdef" for c in args.device_uuid)):
    p.error("dispatch requires --shader and 32 lowercase hexadecimal UUID characters")
  binary = args.binary.resolve(strict=True)
  shader = args.shader.resolve(strict=True) if args.shader else None
  args.output.mkdir(parents=True, exist_ok=False)
  command = [str(binary), "--list"] if args.list else [str(binary), "--device-uuid", args.device_uuid, str(shader)]
  record = {"command": command, "start_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "shader_sha256": hashlib.sha256(shader.read_bytes()).hexdigest() if shader else None,
            "energy": "unknown", "gpu_execution_ns": None,
            "environment": {k: v for k, v in os.environ.items() if k in ("VK_DRIVER_FILES", "VK_ICD_FILENAMES", "VK_INSTANCE_LAYERS", "VK_LAYER_PATH", "MESA_VK_DEVICE_SELECT", "MESA_VK_VERSION_OVERRIDE", "MESA_LOADER_DRIVER_OVERRIDE", "V3D_DEBUG", "V3DV_DEBUG")}}
  # Metadata is local evidence. Review environment values before sharing logs.
  (args.output / "invocation.json").write_text(json.dumps(record, indent=2) + "\n")
  start = time.monotonic()
  with (args.output / "stdout.log").open("w") as stdout, (args.output / "stderr.log").open("w") as stderr:
    child = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
    try:
      result = child.wait(timeout=15)
      outcome = "completed" if result == 0 else "failed-health-review-required"
    except subprocess.TimeoutExpired:
      os.killpg(child.pid, signal.SIGKILL)
      # Do not block again on an uninterruptible kernel task. No automatic retry.
      result = None
      outcome = "deadline-health-review-required"
    except BaseException:
      os.killpg(child.pid, signal.SIGKILL)
      raise
  (args.output / "result.json").write_text(json.dumps({"outcome": outcome, "exit_code": result,
    "wall_seconds": time.monotonic() - start, "automatic_retry": False,
    "health_handoff": outcome != "completed"}, indent=2) + "\n")
  print(args.output)
  raise SystemExit(0 if outcome == "completed" else 3)


if __name__ == "__main__":
  main()
