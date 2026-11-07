# Omarchy 4.5 provisioning implementation

Implementation scope: the assigned owner/user/first-login provisioning and mise paths in the shared `codex/omarchy-4.5-pi4` merge. No index, commit, branch, image-factory, package/update, UI-default, device, or host-installer changes are part of this assignment. Pi 4 4GB and 8GB remain fresh-candidate targets; no hardware validation is claimed.

## Integration requirements for the parent

The owner now calls `omarchy-provision-hardware` before either interactive or Imager setup. Its serialized runner must succeed before an account can be created. This also protects direct manual retries, but does not replace systemd failure propagation. Please install an owner drop-in (alongside the existing grow-root dependency) containing:

```ini
[Unit]
Requires=omarchy-provision-hardware.service
After=omarchy-provision-hardware.service

[Service]
Environment=OMARCHY_PATH=/usr/share/omarchy
```

The existing grow-root drop-in must retain `Requires=omarchy-rpi4-grow-root.service` and `After=omarchy-rpi4-grow-root.service`. Keep SDDM's `Requires=omarchy-provision-owner.service` plus `After=omarchy-provision-owner.service`, and Avahi's owner ordering. The hardware service's existing `Before=` is ordering only and would otherwise release dependents after failure. The service environment is necessary before uwsm exists: `omarchy-provision-owner` and `omarchy-provision-user` now use the required `OMARCHY_PATH` rather than defaulting it, following the runtime-path instructions. The factory agent owns the image target, deferred queue, per-device pacman identity, unit installation, and Linux systemd transaction validation.

Mise must be at least 2026.10.11 before 4.5 declarations are installed; package/version reconciliation belongs to the package agent. Pi owner setup preloads the single staged ARM64 Node archive against `node_bundle.filename` and `node_bundle.sha256` in `/usr/share/omarchy-rpi4/build-manifest.json`. The factory already writes those fields and must keep a valid strict JSON manifest. Archive checks happen before its contents are installed. Fixture overrides are `OMARCHY_NODE_PACKAGE_DIR` and `OMARCHY_NODE_BUNDLE_MANIFEST`; production defaults do not change. Opting out of Omarchy's Node declaration skips the preload, and ordinary runtime/ISO setup uses upstream's offline lazy shims.

The shared `test/shell.d/raspberry-pi-test.sh` is outside this assignment. Its old Node expectations near lines 655–685 require `uname` parsing and `mise use -g node@24.2.0`; those conflict with the requested 4.5 contract. The parent should retire/adapt that block to the new verified preload and config-preservation behavior. The new focused fixtures exercise that behavior without any mise install/use/config command.

## Changes and validation

Resolved the owned conflicts in `bin/omarchy-provision-owner`, `install/user/mise-work.sh`, and `test/shell.d/provision-user-test.sh`. The index remains unmerged deliberately; only the parent may stage and commit the merge. All owned working-tree files are free of conflict markers.

- Owner setup retains the Pi Imager hashed-password, keymap, hostname readback, timezone, Wi-Fi, authorized-key, SSH authentication and passwordless-sudo controls, plus checkout ownership transfer. It also retains the released shared setup form, language/input support, progress renderer, lifecycle preparation, journaled rekey, and shared-ESP boundaries. Other systems' ESP entries are not changed by this work.
- `account-created` checkpoints completed account creation. Retries validate that account, refresh the password separately, and rerun idempotent setup rather than recreating the account. Interrupted account creation before that checkpoint still uses the existing `getent`/`usermod` resume path. Authorized keys are merged without duplicates, preserve existing keys and their final line, and reject symlink destinations.
- A finalizer failure returns its nonzero status from both HDMI and Imager workers, keeps `pending`, `setup-user`, and `account-created`, and leaves `finalize-failed` with the private owner log. Login configuration and completion happen after finalization and rekey succeed. Credential cleanup precedes removal of `pending`; interrupted cleanup retains the account/rekey checkpoints. After actual completion, inability to remove obsolete checkpoints is explicitly logged as housekeeping.
- Exiting the recovery root shell with setup still pending now fails the owner service, preserving the SDDM failure dependency. A successful retry can still finish and release login normally.
- Forced user finalization removes an old `done/finalize-user` marker before running required setup; failure or interruption therefore cannot hide behind that earlier success. Fresh-install migration markers are written only after all required leaves succeed.
- First login includes finalization in failure accounting, clears stale `done/first-run-user`, logs the failure, returns nonzero, and sends an incomplete-setup notification with a retry action. Its completion gate requires both first-run and finalization success, repairing the stale first-run marker the baseline F4 bug could leave.
- Pi owner setup validates the Node archive filename, unique archive selection, factory-manifest SHA-256, archive paths, complete runtime and ARM64 ELF header, then extracts into a private directory on the user's install filesystem and renames the completed version atomically. Bad or missing archives fail required setup without a network fallback. Existing complete versions are kept and are not unpacked again on retries; interrupted staging does not block a fresh attempt. The installed-store preload changes no user mise file or version declaration. Upstream `install/user/mise.sh` remains unchanged and requests `MISE_OFFLINE=true mise reshim --system` and `mise reshim`.
- `--first-install` continues mapping an ordinary runtime caller to `iso-chroot`, while an explicit `provision-owner` context stays intact. The performance agent's first-install Pi leaf at the start of `install/user/all.sh` is preserved; no separate call or runtime reseeding was added.

Affected files in this assignment:

```text
bin/omarchy-provision-owner
bin/omarchy-provision-first-run
bin/omarchy-provision-user
install/user/mise-work.sh
test/shell.d/provision-user-test.sh
test/shell.d/first-run-test.sh
test/shell.d/rpi-owner-hostname-test.sh
test/shell.d/rpi-imager-preseed-test.sh
test/shell.d/rpi45-provisioning-test.sh
test/shell.d/rpi45-mise-offline-test.sh
plans/omarchy-4.5-provisioning-implementation.md
```

Seven focused files passed locally using `/opt/homebrew/bin/bash` 5.3.20, with subprocess Bash resolved through `/opt/homebrew/bin` where needed. Every complete output was retained before being read:

| Test | Log |
| --- | --- |
| `rpi45-provisioning-test.sh` | `/tmp/rpi45-provisioning-test.log` |
| `rpi45-mise-offline-test.sh` | `/tmp/rpi45-mise-offline-test.log` |
| `provision-user-test.sh` | `/tmp/rpi45-existing-provision-user.log` |
| `first-run-test.sh` | `/tmp/rpi45-existing-first-run.log` |
| `rpi-owner-hostname-test.sh` | `/tmp/rpi45-existing-owner-hostname.log` |
| `rpi-imager-preseed-test.sh` | `/tmp/rpi45-existing-imager-preseed.log` |
| `provision-owner-regdom-test.sh` | `/tmp/rpi45-existing-owner-regdom.log` |

The new provisioning fixtures cover required-leaf failure, invalidating stale success, migration-marker ordering, preserving ISO/owner contexts, first-login failure and second-login recovery, both owner workers' hardware prerequisite and finalizer/credential-cleanup failures, reuse of the account, source-checkout ownership requests, encrypted-password argument flow, existing-key preservation, and SSH disabled/key-only/password modes. All system/account/hostname/service operations use fixture boundaries; SSH public-key parsing itself uses a disposable generated key. The new mise fixtures exercise actual archive validation/extraction with small synthetic ARM64 ELF headers; they do not execute those headers. Network/tool stubs reject every curl/wget/npm/node invocation and every mise command except explicitly offline reshim, catching any eager setup call. These assertions prove the setup's command contract, not mise's own implementation.

Regression proof used disposable source snapshots, without checking out or changing the shared repository: replacing only the finalizer, first-login helper, or mise leaf with its `393f48c3` version made the corresponding new fixture fail. Replacing just the owner worker function with its baseline implementation reproduced exit 0 after a finalizer error and failed the expected-status assertion. Logs: `/tmp/rpi45-base-finalizer.log`, `/tmp/rpi45-base-first-login.log`, `/tmp/rpi45-base-owner-worker.log`, `/tmp/rpi45-base-mise.log`.

Bash syntax checks on the eleven reviewed/changed shell paths passed (`/tmp/rpi45-provisioning-syntax.log`). Warning-level ShellCheck with the leaf's shell explicitly set to Bash passed on the three provisioning commands, the mise leaf and two new tests (`/tmp/rpi45-provisioning-shellcheck.log`). Scoped `git diff --check` passed (`/tmp/rpi45-provisioning-diff-check.log`). The existing first-run fixture exits successfully but prints unavailable macOS command/installed-hook diagnostics during optional branches; it does not establish a complete Linux first-login session.

## Remaining validation boundaries

No container, package/image build, host installer/update, real account/service operation, Git mutation, publication, or physical Pi test was performed. No Xcode build was needed. The parent owns consolidated Linux tests and candidate assembly.

On Linux, run the seven focused files above plus `provision-owner-keyboard-test.sh` (which needs Linux keymap/systemd data and GNU sed), `mise-agent-shims-migration-test.sh`, and relevant existing lifecycle/rekey/shared-ESP suites. Test with a real packaged mise at least 2026.10.11 and the actual staged Node archive: generate the real system/user lazy shims in a scratch home with the packaged declarations, then execute the Node shim under `MISE_OFFLINE=true`, verify `node --version`, and confirm a pinned Node version and default-tool opt-out still take precedence. The Mac has no mise binary, so actual shim generation, tool selection, and first-use execution remain unverified here.

Validate the assembled systemd dependency graph, failure propagation, unique package keyring initialization, real unattended boot/retry, and SDDM/Avahi behavior on the parent's disposable Linux candidate. Finally boot both physical Pi 4 memory variants, including offline HDMI and Imager paths, root-growth failure/retry, required finalizer failure, reboot/interruption recovery, SSH policies, and a second normal boot. Progress rendering, real desktop behavior and all physical performance remain unverified.
