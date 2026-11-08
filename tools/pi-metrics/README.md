# Pi metrics protocol v2

Version **2.0.0**, schema **2**. This tracked tool replaces the ignored `build/upstream-pi/stable-4.5/` metrics tools without modifying them. Python 3.9+ standard library only. Target: Linux on the coordinator's designated Pi; controller: Python 3 and OpenSSH. Optional throughput tests require OpenSSL 3, not macOS LibreSSL. Missing dependencies produce unknown measurements, never a zero throughput claim.

## Ownership and safe transport

Only the physical-board coordinator runs `record`. This work did not contact a Pi, run SSH, escalate privileges, or alter the target. The probe reads state and optionally generates CPU load; it never loads a module, writes sysfs, restarts a service, changes a mitigation, mounts a filesystem, or runs a capability experiment. Benchmarks affect temperature, caches and clocks; they are opt-in.

Use an existing SSH key and a dedicated known-hosts file whose fingerprint the coordinator has independently verified. No `.env` is read. The default accepts no password; an explicit coordinator credential transport is documented below. Neither password nor script competes for stdin. SSH receives the Python source on stdin; `sudo -n -- /usr/bin/python3 -I - probe …` executes that exact stream as root and the probe checks effective uid. This is remote command execution with the coordinator's privileges: review the source before running. Do not grant unrestricted passwordless sudo just to run this tool. If the existing authorized noninteractive sudo policy cannot run it, the coordinator must provision a reviewed root-owned collector or run it through their existing interactive terminal workflow. An unprivileged fallback is deliberately absent.

SSH ignores user config, uses batch key authentication, strict host-key checking, a specified identity, no agent/X11 forwarding, no tunnels, no PTY, bounded connect/liveness timeouts and a 120-second controller timeout. Hostnames and users cannot carry shell syntax or SSH options. Metadata crosses the remote shell as quoted base64 JSON. SSH failure, sudo failure, extra stdout, malformed JSON, wrong schema, root failure or mismatched metadata prevents persistence. Diagnostics do not echo remote output or credentials. A timeout interrupts the SSH client; it does not guarantee an already-started remote process has exited, so the coordinator must check before starting another run.

## Record and validate

From the checkout root, **coordinator only** (example, not executed here):

```bash
python3 tools/pi-metrics/metrics.py record \
  --host pi.example --user owner \
  --identity /absolute/path/to/key --known-hosts /absolute/path/to/verified_known_hosts \
  --cohort pi4-4gb-native-v2 --label baseline --experiment idle-cbc --trial 01 \
  --candidate 'installed package set; source/artifact correspondence unknown' \
  --conditions 'cool idle desktop; display 1920x1080@60; cooling unchanged; encrypted USB SSD; no browser; AC supply unchanged' \
  --out /absolute/path/to/private-results --bench
python3 tools/pi-metrics/metrics.py validate /absolute/path/to/private-results/pi4-4gb-native-v2/SAMPLE_UUID.json
```

All metadata arguments are required and persisted. `candidate` should cite exact source commits, package versions and artifact hashes where established; write `unknown` where not established. It is an operator assertion, separate from observed `packages.versions`. `conditions` must describe workload, display/session state, cooling, storage/encryption, supply, cache policy and other changes. Never put passwords, serials or private addresses in metadata. The probe records no hostname, machine ID, serial or raw cmdline. Review private result files before publishing; operator metadata and package versions can still identify a private candidate.

Output is one exclusive UUID JSON file under a traversal-safe cohort directory, mode 0600. There is no shared CSV append race, no silent overwrite, no fabricated v2 baseline. Keep raw results outside tracked source until sanitized. The exact source payload SHA-256, tool/schema versions, UTC start/end times, experiment, trial, label and conditions travel with each sample. A cohort is operator-managed: use separate directories for Pi 4 4GB, Pi 4 8GB, Pi 5, boot lineage and materially different hardware. Validate board identity and nominal RAM in every result; the tool does not certify the operator's cohort choice.

## Measurement contract and unknowns

Every observation has `value`, `unit`, `source`, `status`, and `detail`. `ok` requires a non-null value; unavailable, permission-denied, invalid, error and deliberately unmeasured observations require null. Unknown is never zero, false, unsupported, or a successful capability test. The checked-in JSON Schema describes structure; the dependency-free validator also enforces status/value consistency, root execution and chronological order. Empty dynamic device groups indicate no enumerated device, not a working driver.

- Board revision is exactly one big-endian DT cell. RAM is decoded only for new-style revision codes with a known RAM field, in MiB; old-style/reserved values remain unknown. Nominal RAM differs from kernel-visible `MemTotal` (KiB). `board.model` is an independent observation; CPU part is labeled as a part, not a complete MIDR. Feature flags are observations, not proof of driver usability.
- Config comes first from `/proc/config.gz`, which belongs to the running kernel. Fallback is only `/usr/lib/modules/$(uname -r)/build/.config` with matching `include/config/kernel.release`. No wildcard or unrelated `/boot/config-*` participates. This fallback establishes a declared release match, not cryptographic identity with the booted image; same-release rebuilt headers can still differ. The decoded config hash and source are recorded. Unreadable/corrupt/mismatched config and missing symbols remain unknown, including LTO and HZ. LTO symbols are reported individually, never guessed from absence of `LTO_NONE`.
- KPTI runtime state remains **not measured**. `kpti=` and `mitigations=` tokens record requests only; neither `nokaslr`, x86-style switches, Meltdown status nor `CONFIG_UNMAP_KERNEL_AT_EL0` proves runtime KPTI. Security posture has no “lower is better” score. No mitigation is changed.
- All cpufreq policies and thermal zones are named. Temperatures include zone type and use milliCelsius; cpufreq readings use kHz and firmware ARM clock uses Hz. `scaling_cur_freq` is a policy snapshot, not sustained frequency. Telemetry before and after includes uptime, load, PSI, temperatures and clocks; it cannot resolve transient events or prove sustained behavior. Missing tools/files remain unknown. No timer or background sampler runs.
- `get_throttled` preserves the full bitmask and separately decodes current bits 0–3 and since-boot bits 16–19. A zero is accepted only from a valid `throttled=0x…` response. Missing/failed firmware access is unknown. Historical bits are not current throttling; unrecognized bits remain in the raw mask. Linux thermal readings alone do not exclude firmware throttling.
- Python getpid, open+close of `/dev/null`, and empty-callable loops include Python overhead and use monotonic elapsed time. Values are microseconds per iteration with fixed iteration counts in their source labels, **not bare syscall latency**. These semantics differ from the old `/etc/hostname` and top-level null loop.
- OpenSSL 3 runs one 8192-byte buffer size for one second with `-mr -elapsed -evp` for AES-256-CBC and SHA-256. Machine-readable rates are **bytes/s**, divided by 1,048,576 for MiB/s; non-finite, zero, malformed or multiple rates are rejected. Version and command are recorded. These are userspace benchmarks, not dm-crypt AES-XTS, disk throughput or desktop speed. `/proc/crypto` registrations do not prove hardware capability or availability to OpenSSL; no AES module insertion or forced HWCAP is attempted.
- Installed package names/versions are filtered from `pacman -Q`. Local makepkg flags are deliberately not treated as installed compiler flags. Source/package/artifact correspondence requires separate build evidence. Zram compressor brackets, size, mm_stat, meminfo/CMA, swappiness, THP and PSI are recorded without interpreting missing data as disabled. Zram is RAM compression; encrypted root does not imply per-page zram encryption.
- PCIe output retains device headers with each LnkCap/LnkSta so the first link is not mistaken for the host or VL805. No generation tuning is proposed. Video node count proves neither codec availability nor browser decode. Power/energy, graphical correctness, tail latency, storage and representative application workloads remain unmeasured by this microprobe.

## Experiment and plotting policy

Use repeated matched trials, one changed variable, idle/cooling criteria established before each run, and reversal trials where feasible. Persist all trials and record rejected attempts in the experiment log (the tool does not create valid sample rows for failures); do not select the best run. Compare distributions and variability only within matched cohorts, workloads and protocol versions. A one-second microbenchmark plus two telemetry snapshots is insufficient for sustained clock or energy claims. There is no automatic improvement-colored chart or security-state score: the old plotter connected incompatible evidence and treated lower KPTI as progress. Future plots must facet by cohort/protocol/experiment, show trial spread and unknown gaps, and label throughput separately from state. Do not join legacy rows into a v2 curve or claim Raspberry Pi OS parity without a matched baseline.

## Local verification

```bash
python3 -m unittest discover -s tools/pi-metrics/tests -v >/tmp/pi-metrics-tests.log 2>&1
cat /tmp/pi-metrics-tests.log
python3 tools/pi-metrics/metrics.py --help
```

Tests exercise endian/RAM parsing, malformed throttles, byte-rate units, unknown/permission handling, mismatched and unrelated configs, source precedence, transport quoting, actual stdin subprocess delivery, privilege rejection, schema rejection and unavailable-host collection. A real local OpenSSL 3 throughput invocation checks its output parser without SSH. The unavailable-host test only substitutes platform/euid checks to exercise missing-file behavior on macOS; it does not validate root access or Pi behavior. Linux root collection, sudo policy, host-key/key authentication, target tool availability, telemetry correctness and matched trials await coordinator validation. No Apple toolchain or build is used.

## Coordinator credential transport

For a board whose existing authorized sudo access requires a password, `record --sudo-password-stdin` accepts exactly one nonempty password line from controller stdin. The caller supplies the existing credential without printing it; never put it in argv or metadata. The SSH stdin frame is password newline followed by source. The remote shell reads the line and buffers the complete source before invoking `sudo -S … python3 -I -c "$code"`; sudo receives only the password pipe and Python executes the buffered source as root. Strict host-key/key controls and validation are unchanged. Metadata records `ssh-key-strict-hostkey-sudo-S-framed`. No passwordless rule is granted. Do not use multiline credentials. Default `record` continues using sudo-n/source stdin as described above.
