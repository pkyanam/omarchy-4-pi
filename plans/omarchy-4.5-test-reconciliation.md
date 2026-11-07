# Omarchy 4.5 Pi test reconciliation

Reconciled the assigned legacy tests, upgrade guidance and CI in shared `codex/omarchy-4.5-pi4`. Scope was `test/shell.d/raspberry-pi-test.sh`, `rpi-update-safety-test.sh`, `rpi-upgrade-guide-test.sh`, `rpi-upgrade-guide-fixture.py`, `docs/pi-upgrade.md`, `.github/workflows/pi-checks.yml`, and this report. No production code, index, branch, commit, container, package/image build, host installer/update or device operation was changed/run by this agent.

## Changes

- The broad Pi suite retains device detection, KMS setup/idempotence, native power/temperature diagnostics, DRM/EDID/ELD and input/service failure cases, ext4/Snapper and Limine guards, external package-cache staging, and selectable/path-safe Imager catalog checks. Removed rolling-only mirrors, obsolete source reconstruction/JSON formatting, old source-build and other implementation-string assertions superseded by behavioral `rpi45-*` suites. Preserved the parent's comment delegating Node preload coverage to `rpi45-mise-offline-test.sh`.
- Its rootfs fixture now uses signed stable templates, the 4.5 required package/runtime versions, actual managed firmware configuration, U-Boot plus the separate Linux image/DTB, the AArch64 titlebar plugin, deferred trusted image/keyring state and the growth → hardware → owner → SDDM dependencies. A tiny real shallow Git checkout and the actual strict manifest writer supply matching provenance/inventory/Node checksums. The audit/schema/ownership checks are never mocked. Synthetic ELF headers and firmware/Node bytes test audit behavior, not real binary execution or firmware validity.
- `--rootfs-audit-only` permits a separate root CI run without replaying portable diagnostics. Unprivileged runs build the same fixture and demand that real root ownership is its sole audit failure, then explicitly skip the corruption cases requiring a passing root-owned baseline. Root mode runs actual audit failures for dangling Wi-Fi firmware, missing growth/hardware/SDDM requirements, corrupted Node, valid-JSON inventory/version mismatches, x86 Quickshell, PC firmware, AppleDouble, writable first-boot state, retained factory pacman identity, missing Linux Image and overriding vendor zram.
- Update safety uses real temporary Git metadata and the current stable profile, ordered repositories, signature/cache/core-protection contract. Legacy profiles fail every update entry point before fetch/trust/package operations. Retry/order/artifact-pair coverage remains in the new focused suites. Network/privileged/package doubles reject mutations; only specific read-only Git queries reach real Git.
- The guide replaces the mutable-main bootstrap with fresh-media 4.5 transition instructions and whole-card rollback. It distinguishes future clean reviewed `origin/main` updates from intentionally refused unpublished/dirty candidates. Its fixture executes actual updater/installer guard paths, including an old updater sourcing new installer leaves; it no longer fakes an updater or copies documentation prose into assertions. No physical validation is claimed.
- Ubuntu 24.04 CI installs Bash fixture dependencies including libarchive, Python/YAML, Lua, jq, rsync, OpenSSH and GNU utilities. It retains existing focused gates, adds the guide and every `rpi45-*` suite, requires an unprivileged first-boot/provisioning runner plus a separate root audit, saves complete logs, and fails unexpected skips. Summaries explicitly separate x86 source fixtures from native ARM package/image and physical-board gates. The workflow was parsed, not dispatched.

## Validation evidence

All local commands used `/opt/homebrew/bin/bash` 5.3.20 with subprocess Bash resolved through `/opt/homebrew/bin`. Complete output was captured before reading it.

| Check | Result | Complete log |
| --- | --- | --- |
| Broad Pi suite on Mac | Portable diagnostics/catalog checks passed; full 4.5 fixture passed all invariants except required root ownership, which was correctly refused; root-only corruption cases explicitly skipped | `/tmp/rpi45-reconcile-raspberry.log` |
| Update safety after parent guard fix | Passed, including inherited-policy rejection | `/tmp/rpi45-reconcile-update-safety.log` |
| Upgrade guide behavioral fixtures | Eight checks passed against actual guards/installer leaves | `/tmp/rpi45-reconcile-upgrade-guide.log` |
| Owned shell syntax and warning-level ShellCheck | Passed | `/tmp/rpi45-reconcile-syntax.log`, `/tmp/rpi45-reconcile-shellcheck.log` |
| Workflow YAML/embedded Bash syntax and ShellCheck, Python compilation | Passed using local Ruby YAML parser; CI installs its Python YAML dependency | `/tmp/rpi45-reconcile-workflow.log` |
| Scoped whitespace check | Passed | `/tmp/rpi45-reconcile-diff-check.log` |
| Native ARM64 Linux rootfs audit, run by parent | Baseline plus all ten fault groups passed, exit 0 | `build/validation/linux/rootfs-audit.log` |
| Native ARM64 Linux update safety, run by parent | Passed after the production guard fix | `build/validation/linux/rpi-update-safety.log` |

A real regression was found: exported `OMARCHY_RPI4_PACKAGE_POLICY=stable-4.5` let a legacy profile without that marker pass the guard. The added assertion failed before the production fix; evidence is `/tmp/rpi45-reconcile-inherited-policy-red.log`. The parent fixed the guard to clear inherited source/profile/policy values before reading the installed profile. This agent made no production edit. The final safety suite passes locally and in the parent's Linux log.

The parent separately reported all new package/build/update/performance/image suites passing native ARM64 Linux, including Lua and the unprivileged real first-boot runner; logs are under `build/validation/linux/rpi45-*.log`. The parent also reconciled the unowned screensaver, optimization recipe-pin and performance source-stage fixtures, and reports those passing. These are parent-run fixture results, not an image build or board result. No aggregate suite was rerun by this agent.

## Remaining gates

Run the revised CI job in GitHub; local syntax/fixture checks do not prove its hosted execution. The parent coordinates the native image build after clean integration, real libalpm dependency solving/signatures, native package ownership/artifacts and Hyprland/Qt/titlebar loading, strict mounted-image audit/manifest/catalog integrity, offline Node/mise execution and actual systemd boot/failure/retry transactions. Rootfs fixture headers and fake parser receipts do not establish those results.

Physical Pi 4 Model B 4GB and 8GB remain independent gates: spare-media boot, root growth, HDMI/Imager owner setup and recovery, offline trust uniqueness, networking/SSH, display/input/audio, rendering/media paths, cgroup/resource enforcement, lock/wake, thermal and responsiveness workloads. Keep the working card intact. No Pi 5, in-place rolling downgrade, performance parity, release or hardware qualification follows from these tests.
