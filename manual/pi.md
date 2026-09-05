# A considerate Pi workspace

Omarchy 4 Pi is designed for Raspberry Pi 4 Model B with **4GB+ RAM**. Keep your familiar Omarchy terminal, editor, themes, and agent workflow; give heavy jobs a budget so the desktop has room to breathe.

These commands target the new alpha track; they are not in the first stable downloadable image.

## Ask the board how it feels

```bash
omarchy pi report
omarchy pi report --json
omarchy-pi-status
omarchy-pi-check
```

The report shows Linux-visible RAM, CPU policy, temperature, voltage alarm, compressed-swap statistics, and CPU/memory/I/O pressure. Missing sensors are reported as unknown, not healthy. A clear current voltage alarm does not prove that no power problem happened earlier.

The JSON report is suitable for giving to an agent. It intentionally excludes hostnames, IP addresses, serial numbers, process arguments, provisioning credentials, and agent account data. Still review anything before posting it publicly.

## Keep a build from taking over your desktop

```bash
omarchy pi run --plan -- make
omarchy pi run -- make
```

The first command only prints the proposed launch. The second runs your command in a temporary systemd user scope with CPU and memory limits and RAM-aware Make/Cargo/CMake parallelism. It keeps your terminal, working directory, and environment. Explicit build flags supplied by the command can override the build-job hints, but not the scope's resource limits.

On a four-core Pi, the CPU ceiling is three cores' worth of execution time, not a dedicated reserved physical core. Memory reclaim begins at 50% of physical RAM and the final ceiling is 65%. A job that cannot fit may be killed. Save your work, start only one heavy scoped job at a time, and use a remote machine for workloads that cannot fit locally. Some I/O controls depend on the kernel and controller setup.

You can replace `make` with your installed agent CLI or a shell. This is not a security sandbox: the command still has your file and network access. It does not grant sudo or add auto-approval flags. Background services launched through another manager may not remain inside the scope.

## Give an agent useful guardrails

A good starting request is:

> Inspect this Raspberry Pi 4 using `omarchy pi report --json` and the relevant source. Explain the bottleneck before changing anything. Keep ARM repositories, the Pi hostname, boot configuration, thermal protections, and my personal settings intact. Ask before system updates, package installs, stress tests, remote services, or rebooting. Put any heavy build inside `omarchy pi run` and tell me if its budget is insufficient.

Use the Omarchy default-agent picker and normal launchers for your preferred provider. Hosted inference lets the Pi concentrate on your workspace. Selecting a local model does not make it suitable for 4GB RAM; its model weights, context cache, and other applications all need space.

## Clocks are not a first-aid kit

The alpha ships at stock clocks, with an implemented opt-in tuner. Start with `omarchy pi tune preview boost`; applying a profile requires an interactive risk/recovery confirmation, a backup, cooling, and healthy sensors. Read the [clock trial and SD-card recovery guide](../docs/pi-tuning.md) before applying anything. The guide also explains the new CPU, memory, build, and logging defaults. Never disable thermal protection to obtain a benchmark result.
