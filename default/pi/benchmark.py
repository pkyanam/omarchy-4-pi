"""Small repeatable CPU sample, not a hardware stability certification."""
import argparse
import hashlib
import json
import multiprocessing
import os
import platform
import time

from tune import Refused, Tuner


def worker(stop, results, deadline):
  block = b"\x5a" * 1048576
  count = 0
  while not stop.is_set() and time.monotonic() < deadline:
    hashlib.sha256(block).digest()
    count += 1
  results.put(count)


def run(seconds, jobs, tuner):
  board = tuner.board()
  before = tuner.health()
  context = multiprocessing.get_context("spawn")
  stop, results = context.Event(), context.Queue()
  started = time.monotonic()
  deadline = started + seconds
  children = [context.Process(target=worker, args=(stop, results, deadline)) for _ in range(jobs)]
  peak = before["temperature_c"]
  reason = None
  try:
    for child in children:
      child.start()
    while time.monotonic() < deadline:
      time.sleep(min(1, max(0, deadline - time.monotonic())))
      health = tuner.health(limit=75)
      peak = max(peak, health["temperature_c"])
      if any(child.exitcode not in (None, 0) for child in children):
        raise Refused("Benchmark worker failed.")
  except (Refused, OSError, ValueError, KeyboardInterrupt) as error:
    reason = str(error) or "Interrupted"
  finally:
    stop.set()
    for child in children:
      if child.pid is not None:
        child.join(timeout=2)
        if child.is_alive():
          child.terminate()
          child.join()
  elapsed = time.monotonic() - started
  counts = []
  for child in children:
    if child.exitcode == 0:
      counts.append(results.get(timeout=2))
    else:
      reason = reason or "A benchmark worker did not complete."
  results.close()
  return {"schema": 1, "workload": "sha256-1MiB-v1", "board": board,
    "kernel": platform.release(), "jobs": jobs, "requested_seconds": seconds,
    "elapsed_seconds": round(elapsed, 3), "completed": reason is None,
    "stop_reason": reason, "processed_mib": sum(counts),
    "mib_per_second": round(sum(counts) / elapsed, 2),
    "temperature_before_c": before["temperature_c"], "temperature_peak_c": peak,
    "note": "CPU microbenchmark only; repeat at stock clocks and compare medians. Not a full stability or desktop benchmark."}


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--seconds", type=int, default=30, choices=range(10, 301), metavar="10..300")
  args = parser.parse_args()
  # The enclosing scope also limits resources. Two low-memory workers on a
  # 4GB Pi leave room for the desktop and do not hammer the SD card.
  jobs = min(2, max(1, (os.cpu_count() or 1) - 1))
  try:
    report = run(args.seconds, jobs, Tuner())
  except (Refused, OSError, ValueError) as error:
    parser.exit(1, f"Benchmark refused: {error}\n")
  print(json.dumps(report, indent=2))
  return 0 if report["completed"] else 1


if __name__ == "__main__":
  raise SystemExit(main())
