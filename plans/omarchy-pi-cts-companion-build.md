# CTS companion split-package build — 2026-11-08

Status: the real small production companion archive builds offline using normal makepkg source/dependency checks. Archive metadata, payload identities, saved-FDT overlay application and adjusted ALPM lifecycle fixture pass. No full kernel build, physical FAT transaction, boot or radio qualification occurred. No Pi/SSH/card access, host installation, heavy compiler, VM changes, staging, commits, messages or subagents were used. The parent's approved temporary 4 GiB VM and active Zstd lane were left unchanged.

Candidate root: `build/upstream-pi/stable-4.5/cts-kernel-candidate/`. Relative evidence paths below are under that root. Read root AGENTS, `plans/omarchy-pi-cts-firmware-validation.md`, `plans/omarchy-pi-cts-build-preflight.md` and `logs/parent-cache-preflight.log` before implementation. Existing evidence is preserved. This report supersedes only the earlier claim that kernel 32.2 and support must be installed in the companion builder; it does not supersede kernel, deployment or recovery gates.

## Packaging change and makepkg semantics

`firmware/PKGBUILD` now declares `pkgbase=raspberrypi-4-pftf-cts`, a single-element pkgname array, and `package_raspberrypi-4-pftf-cts()`. Its output function declares exactly `linux-omarchy=7.3-32.2`, `raspberrypi-4-support`, `python` and `util-linux`. Top-level `makedepends=('dtc')` remains. Version, architecture, source list, source checksums and payload install paths are unchanged. The helper, hooks, configuration, baseline and DT source are byte-identical to the preserved originals.

The installed `/usr/bin/makepkg` and `/usr/share/makepkg/util/pkgbuild.sh` are preserved in `companion-build/attempt-1/installed-makepkg.log`. makepkg recognizes a package-specific function as split packaging even with one output; it resolves top-level depends/makedepends before the build, executes the output function under fakeroot and writes that function's runtime dependencies into `.PKGINFO`. This follows the existing kernel recipe's packaging model. The actual build demonstrates these semantics without installing either target runtime package.

`build-inside.sh` and `kernel/offline-inputs.sh` now explain this distinction at the early gate. Their executable gate logic is unchanged: every source is required and actual `pacman -T base-devel dtc kmod` plus recipe top-level depends/makedepends must succeed before expensive work. The firmware recipe declaration change fixes the premature failure. Kernel dependency, config, source and archive checks are not weakened. No runtime dependency is removed from the shipped package, no package-manager metadata is fabricated for the production build, and no dependency installation, `--nodeps`, `--skip*` or source/signature bypass is used.

Only corresponding existing INPUTS entries were refreshed, plus the packaging fixture entry. Current hashes:

| Input | SHA256 |
| --- | --- |
| `firmware/PKGBUILD` | `89937b677053df272a61be859184f1f3b0b8375905132cfcd15812d72868ab8d` |
| `build-inside.sh` | `ee1d81e644e417befcdc648fb0633a651e679ff5de787c15c091bf2345e1db2f` |
| `kernel/offline-inputs.sh` | `802070ff2f5dba2bdb784115c5d78c419cc13b806718099f71e6308e1db39ee1` |
| `firmware-tests/alpm.py` | `1df9934abbbfd3bb719f96ea08a389aa3c7fb0a240beb4268b503549218fe8e9` |
| `INPUTS.sha256` | `8fe5bcdbf278b2ffaccac36c2a1401d50cd5c874c6aa020948c845262b31cc9a` |

## Production build and archive verification

Archive: `companion-build/attempt-2/raspberrypi-4-pftf-cts-1-1-aarch64.pkg.tar.zst`, 8,069 bytes, SHA256 `47c5e4d4e8dc913730d5625235c1be9ca73e9b8eebb74d84fcb8cde2dfd1b139`.

`attempt-2/build.sh` runs real dependency preflight, `makepkg --printsrcinfo`, `makepkg --verifysource --noconfirm` and `makepkg --noconfirm` as the image's builder user. It uses real production source/baseline files, dtc, fakeroot and single-thread compression. `build.log` preserves full output; `worktree/` preserves source and built payload. `installed-packages.txt` and `absent-runtime.txt` establish that actual build dependencies were installed while candidate kernel 32.2 and support were absent. In particular support 1-3's desktop/GPU firmware dependency closure was neither installed nor faked to obtain this archive.

`verify.py` and `verify.log` establish:

- Exact name, pkgbase, version, aarch64 architecture and the four runtime dependencies in the real archive `.PKGINFO`; `PKGINFO`, `BUILDINFO` and `archive-files.txt` are retained.
- All seven installed helper/hook/baseline/config files match production source bytes. The packaged overlay matches the actual dtc build output; hashes are in `payload-hashes.json` and decoded overlay in `cts.dts`.
- Real fdtoverlay against `current.fdt`, followed by unchanged `verify-fdt.py`, adds precisely one AUX `uart-has-rtscts` property and preserves every other property, including DMA. Output `cts.fdt` is an offline fixture, not observed boot state.
- Both full kernel and firmware offline source/dependency preflights pass with the parent's existing cache mounted read-only. No kernel prepare/build is invoked.

All containers use the existing pinned image `sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2`, 0.25 CPU, 128 MiB RAM and memory-swap total 128 MiB (zero extra swap), 32 PIDs, no network, no privileged mode and no devices. Production runs explicitly use `--pull never`. Storage is disk-backed, with candidate sources read-only and private evidence writable. Capabilities are dropped; the build adds only CHOWN/SETUID/SETGID to run the existing builder user, verification adds none. Containers are retained stopped. Successful build peak is 65,392,640 bytes (62.36 MiB), cgroup CPU usage 1,734,631 microseconds; memory max/oom/oom_kill events are zero. Container inspections and full cgroup counters are retained alongside logs.

`attempt-1/build.log` preserves an initial failure writing the builder-owned existing `/home/builder/.makepkg.conf` as capability-restricted root. No build occurred in that attempt. `attempt-2` corrects this by writing that file as builder; no capability escalation or dependency bypass was added. Both stopped containers and all original logs remain. `attempt-1/before/` preserves original owned scripts, full firmware source and original INPUTS, with `before.sha256`. `attempt-2/audit.py` / `audit.log` record source byte identity, shell/Python syntax, complete owned diffs, container limits/exits/no OOM and successful complete INPUTS verification. Evidence files have their own `companion-build/EVIDENCE.sha256`; the directory is already ignored by the repository's build rule.

## Adjusted lifecycle fixture and acceptance holds

`firmware-tests/alpm.py` now invokes the actual new output function before collecting its runtime dependencies and layout. It asserts the exact four metadata dependencies and adds a real ALPM support-removal rejection. `firmware-tests/results/companion-split-1/test.log` and `container.json` retain the passing run. The fixture alone uses explicitly synthetic metadata-only kernel/support packages and synthetic media/overlay bytes, as before; those never enter the production build environment. The unchanged helper's 25-test suite was not rerun. runpy loads its fixture class without executing that suite.

The updated ALPM run proves kernel downgrade/removal and support removal fail dependency resolution, opted-in companion removal fails its real pre-hook, and explicit installed-helper restore permits companion removal and subsequent dummy-kernel downgrade. First install still has no newly installed pre-hook: its post-hook fails for missing configuration, pacman returns **0**, and the package remains installed. This is a stop/no-reboot condition, requiring the parent's extracted-archive first-install preflight, explicit helper/media readback and recovery acceptance. A successful archive build or pacman exit does not release that hold.

There is no physical FAT durability/power-loss qualification, real firmware-card transaction, final boot/live FDT observation, CTS/radio qualification, full kernel build, full 32.2 archive-set verification or cross-version kernel/DT/firmware rollback result here. Parent retains those gates and separate ESP/media recovery. The demonstrated same-version native root snapshot restore/reboot remains accepted; no new permission gate is introduced. Mutable RPI_EFI.fd NVRAM remains covered by the private exact baseline and can reject legitimate variable changes. This is not public NVRAM update support; do not widen hashes or overwrite variables to pass it.
