#!/usr/bin/env python3
"""Compile only inside a parent-managed private cgroup-v2 bounded builder."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


def main():
  if len(sys.argv) != 2:
    raise SystemExit("usage: python3 gpu-compute-build.py NEW_OUTPUT_DIR")
  # Parent may provision official binary dependencies in its disposable builder.
  # This recipe never provisions, changes limits, or executes Vulkan.
  group = Path("/sys/fs/cgroup")
  try:
    quota, period = (group / "cpu.max").read_text().split()
    memory = (group / "memory.max").read_text().strip()
    swap = (group / "memory.swap.max").read_text().strip()
  except (OSError, ValueError):
    raise SystemExit("missing prerequisite: existing cgroup-v2 bounded Linux build environment")
  if (quota == "max" or int(quota) <= 0 or int(period) <= 0 or int(quota) * 4 > int(period)
      or memory == "max" or swap == "max" or int(memory) + int(swap) > 256 * 1024 * 1024):
    raise SystemExit("requires cgroup v2 <=0.25 CPU and RAM+swap <=256MiB")
  for name in ("cc", "pkg-config", "glslangValidator", "spirv-val"):
    if not shutil.which(name):
      raise SystemExit("missing prerequisite: " + name + "; parent must provision private builder")
  subprocess.run(["pkg-config", "--exists", "vulkan >= 1.2"], check=True)
  flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "vulkan"], text=True))
  src = Path(__file__).resolve().parent
  out = Path(sys.argv[1]).resolve()
  out.mkdir(parents=True, exist_ok=False)
  # Preserve full output on failure; a partial artifact is never a qualified binary.
  with (out / "build.log").open("w") as log:
    for command in (
      ["glslangValidator", "--version"],
      ["spirv-val", "--version"],
      ["cc", "--version"],
      ["pkg-config", "--modversion", "vulkan"],
      ["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", "comp", "-o", str(out / "box.spv"), str(src / "gpu-compute-box.comp")],
      ["spirv-val", "--target-env", "vulkan1.2", str(out / "box.spv")],
      ["cc", "-std=c11", "-O0", "-Wall", "-Wextra", "-Werror", "-fsyntax-only", str(src / "gpu-compute-vulkan.c"), *flags],
      ["cc", "-std=c11", "-O0", "-Wall", "-Wextra", "-Werror", str(src / "gpu-compute-vulkan.c"), "-o", str(out / "gpu-compute-vulkan"), *flags],
    ):
      log.write(shlex.join(command) + "\n")
      log.flush()
      subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=60, check=True,
                     env={**os.environ, "MAKEFLAGS": "-j1"})
  (out / "BUILD-COMPLETED").write_text("Compiled and SPIR-V validated; GPU execution/correctness unverified.\n")
  print(out)


if __name__ == "__main__":
  main()
