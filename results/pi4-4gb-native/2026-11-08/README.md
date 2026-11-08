# CPUFreq screening experiment

Status: physically measured on the designated 4GB Pi 4; rejected as evidence for changing the governor. No persistent configuration change. The script restored schedutil between trials and on exit; a separate SSH read confirmed schedutil after completion. There was no package, mitigation or clock-limit change.

Hypothesis: forcing performance instead of schedutil improves sustained SHA-256 throughput. Workload: Python hashlib, four processes, 1 MiB blocks, 20-second target per trial, ABBA order. Python/OpenSSL and kernel versions are in the raw JSON. Start gate: temperature at most 48°C, native voltage alarm zero. Stop: 75°C or voltage alarm. The script samples requested CPUFreq and temperature once a second. Firmware actual clocks, throttle history, energy, tail latency and application responsiveness were not measured. This is a compute screening trial, not desktop or Pi OS parity.

| Order | Governor | MiB hashed / 20 s | Worker CPU seconds | Temperature range °C |
| --- | --- | --- | --- | --- |
| A1 | schedutil | 632.60 | 78.48 | 40.894–63.296 |
| B1 | performance | 599.65 | 75.55 | 45.277–67.192 |
| B2 | performance | 634.65 | 78.70 | 46.738–67.679 |
| A2 | schedutil | 637.30 | 79.20 | 47.225–69.627 |

All sampled policy frequencies were 1800000 kHz and sampled native voltage alarms were zero. Those are not firmware clock/throttle proofs. Start temperatures differed within the gate and the desktop was shared; lower worker CPU time in B1 suggests contention, not proof of a governor regression. Process startup consumes part of the shared 20-second deadline, so throughput is a bounded-workload rate rather than isolated steady-state hashing throughput. Keep every trial; do not select B2 to manufacture an improvement. The candidate has no demonstrated repeatable benefit and is not retained.

Raw evidence: `cpufreq-abba.json`; reproducer: `tools/pi-experiments/cpufreq-trial.py`. Source provenance is its tracked commit/hash, not the legacy metrics series. This separate experiment does not append incompatible measurements to the six legacy rows. No 8GB/Pi 5 or Raspberry Pi OS baseline exists here. Another trial is justified only after resolving firmware telemetry and controlling the start/session conditions, or for a different representative workload.
