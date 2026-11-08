#!/usr/bin/env python3
"""One-shot, read-only Linux evidence; no subprocesses, policy writes or polling.

Run only by the Pi owner at explicit workload phase boundaries. Output can
include local process/device names; review before publishing. No dm tables,
keys, environment, command lines or disk contents are read.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import time


def read(path):
  try:
    return {"status": "ok", "value": Path(path).read_text().strip()}
  except OSError as error:
    return {"status": "unavailable", "value": None, "detail": error.strerror}


def capture(pids):
  started = time.monotonic_ns()
  paths = [
    "/proc/sys/kernel/random/boot_id", "/proc/uptime", "/proc/meminfo",
    "/proc/vmstat", "/proc/diskstats", "/proc/buddyinfo", "/proc/pagetypeinfo",
    "/proc/pressure/cpu", "/proc/pressure/memory", "/proc/pressure/io",
    "/proc/sys/vm/swappiness", "/sys/module/zswap/parameters/enabled",
    "/sys/module/usbcore/parameters/usbfs_memory_mb",
  ]
  thp = Path("/sys/kernel/mm/transparent_hugepage")
  paths += [str(thp / name) for name in (
    "enabled", "defrag", "shmem_enabled", "hpage_pmd_size",
    "khugepaged/defrag", "khugepaged/pages_collapsed", "khugepaged/full_scans",
  )]
  paths += [str(p) for p in sorted(thp.glob("hugepages-*kB/enabled"))]
  paths += [str(p) for p in sorted(thp.glob("hugepages-*kB/stats/*")) if p.is_file()]
  paths += [str(p) for p in sorted(Path("/sys/kernel/mm/cma").glob("*/*")) if p.is_file()]
  devices = {}
  for dev in sorted(Path("/sys/class/block").glob("*")):
    if dev.name.startswith("loop"):
      continue
    fields = ("stat", "size", "queue/scheduler", "queue/logical_block_size",
              "queue/physical_block_size", "queue/discard_max_bytes",
              "queue/nr_requests", "device/queue_depth")
    if dev.name.startswith("zram"):
      fields += ("comp_algorithm", "disksize", "mm_stat", "io_stat", "bd_stat", "backing_dev")
    devices[dev.name] = {
      "attributes": {name: read(dev / name) for name in fields},
      "slaves": sorted(p.name for p in (dev / "slaves").glob("*")),
    }
  processes = {}
  for pid in pids:
    proc = Path("/proc") / str(pid)
    entry = {name: read(proc / name) for name in ("comm", "stat", "status", "smaps_rollup", "io")}
    # Keep mapping-level THP accounting without filenames or virtual addresses.
    smaps = read(proc / "smaps")
    if smaps["status"] == "ok":
      prefixes = ("Rss:", "Pss:", "Anonymous:", "AnonHugePages:", "Swap:", "VmFlags:",
                  "KernelPageSize:", "MMUPageSize:", "THPeligible:")
      smaps["value"] = [line for line in smaps["value"].splitlines() if line.startswith(prefixes)]
    entry["smaps_accounting"] = smaps
    # Records describe fd references, not additive allocations. Deduplicate by
    # drm-pdev/device and drm-client-id offline before summing; shared BOs may
    # still appear across clients. Absence of driver support is unknown, not 0.
    fdinfo = {}
    try:
      for fd in sorted((proc / "fdinfo").iterdir()):
        data = read(fd)
        if data["status"] == "ok":
          lines = [line for line in data["value"].splitlines() if line.startswith("drm-")]
          if lines:
            fdinfo[fd.name] = lines
      entry["drm_fdinfo"] = {"status": "ok", "value": fdinfo,
                             "detail": "empty does not establish zero GPU memory"}
    except OSError as error:
      entry["drm_fdinfo"] = {"status": "unavailable", "value": None, "detail": error.strerror}
    processes[str(pid)] = entry
  return {
    "schema": "omarchy-pi-low-level-snapshot-v1",
    "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "kernel": platform.release(), "euid": os.geteuid(),
    "files": {path: read(path) for path in paths},
    "block_devices": devices, "processes": processes,
    "elapsed_ns": time.monotonic_ns() - started,
    "limitations": ["non-atomic sequential snapshot", "system-wide counters include other clients",
                    "no selected active dm-crypt transform or queue flags established",
                    "GPU memory is not generally included in RSS or uniquely additive across clients"],
  }


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--label", required=True, help="workload phase, e.g. thp-A1-before")
  parser.add_argument("--pid", type=int, action="append", default=[], help="explicit shell/browser/compositor PID; repeatable")
  args = parser.parse_args()
  if platform.system() != "Linux":
    parser.error("Linux-only; this tool does not connect to a device")
  if any(pid <= 0 for pid in args.pid):
    parser.error("PIDs must be positive")
  result = capture(args.pid)
  result["label"] = args.label
  result["script_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
  print(json.dumps(result, indent=2))


if __name__ == "__main__":
  main()
