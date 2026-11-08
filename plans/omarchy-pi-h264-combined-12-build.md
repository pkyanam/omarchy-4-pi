# Exact twelve-patch H.264 diagnostic build

November 8, 2026. **PASS: all four actual external modules compile, modpost, link and generate BTF. NONDEPLOYABLE. Containers stopped; local heavy-build lease returned.** One compilation attempt, no additional fixes or source changes, no Pi work.

## Result and exact regression boundary

The retained [whole compile log](../build/upstream-pi/stable-4.5/h264-combined-12/compile.log) and `compile.exit` record successful VCHIQ, VCSM, MMAL and codec external module compilation using `make -C /work/headers/usr/lib/modules/7.3.0-32.1-omarchy/build M=/work/source -j1 modules`. Modpost and BTF generation ran for all four modules without bypasses. GCC 16.1.1 20260430 and GNU ld 2.46.0 were used. The unchanged external Makefile selected the four mutually dependent modules together; nothing forced in-tree status, CRC, vermagic, fake exports or namespace exemptions.

The [previous eleven-patch compile](omarchy-pi-h264-combined-build.md) remains the real red regression evidence: nonexistent `vchiq_register_connected_callback` stopped VCSM compilation. Fresh replay of the first eleven tracked patches matched every C/header byte of that actual failed compiled source. Patch 0012 then changed only the VCSM probe call to `vchiq_add_connected_callback_sync(device, vc_sm_connected_init)`, preserving arguments, int return handling and paired `vchiq_remove_connected_callback`. `source-prefix-11.json`, `patch12-delta.json`, `source-before.json` and `series.json` preserve that boundary. The exact existing Makefile also matches the failed attempt. The unchanged `free_kernel_id` unused-function warning is separate; no cleanup was attempted.

Historical owner-unit tests supplied a boundary stub under the nonexistent API name. Those passes do not validate real transport API integration. They were not rerun or relabeled. This actual combined build closes the compile/link API gap only; old six-patch module hashes do not validate this series.

## Authenticated inputs and preservation

Evidence root: `build/upstream-pi/stable-4.5/h264-combined-12/`. All existing patches, helpers, sources, tests and reports were read-only. The tracked replay helper streamed only the Raspberry Pi platform/header subtrees from the exact archive; no full kernel extraction occurred. A local Python observer intercepted completed patch invocations solely to check the eleven-patch boundary before patch twelve, without changing helper bytes or patch commands. All twelve used `--fuzz=0`; final source is 30 C/header files plus the existing external Makefile.

- Source archive SHA-256: `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`.
- Headers archive SHA-256: `1c90e860325eed52865869c060f762718784f9bda9cc9d7978fa636ce74f89e1`.
- Existing arm64 image: `sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2`.

The case-sensitive Linux tree `omarchy-pi-h264-combined-11-work:/headers` was mounted read-only at `/input/headers`, then cloned to new volume `omarchy-pi-h264-combined-12-work:/headers`. All **22,575 regular archive files**, including the four outside the kernel build subtree, authenticated byte-for-byte on Linux. No Mac-extracted headers were used. Whole original and clone manifests before and after are equal, including symlink targets; `headers-changes.json` is empty. Source C/header and Makefile hashes remained unchanged, and the host copy matches every volume artifact hash. `inputs-before.json` equals `inputs-after.json`, covering both archives, replay helper, series, external Makefile and twelve patches. Patches 0001–0011 also match the preserved candidate patches byte-for-byte.

Protected kernel hashes remained:

| Input | SHA-256 |
| --- | --- |
| `.config` | `3b12d3dd8d8b0b24ab95ef96bb1b3388d2440a5bda069ecd74f3c7984a2fd51d` |
| `Module.symvers` | `9717ce5b1296bf82b456540fc72c7bb6609e0bfd4cd1049981b78a3232774c31` |
| `vmlinux` | `7ef2cbdc17b62649f168da6f8bf49ad2be8de4e85dc2556675ff4d279bae3a08` |

Target configuration enables modules/unloading, MODVERSIONS, DWARF5 and module BTF. Exact release is `7.3.0-32.1-omarchy`; this task does not independently compare the installed private CTS repack.

## Artifact checks and hashes

[modules.json](../build/upstream-pi/stable-4.5/h264-combined-12/modules.json), `module-symbol-resolution.json`, `symbols-elf.log`, `modules-abi.log` and `verification.json` retain the checks. Every module is AArch64 ELF with actual DWARF version 5, nonempty generated `.BTF` and `.BTF.base` sections with valid magic/version/bounds, and vermagic `7.3.0-32.1-omarchy SMP preempt mod_unload modversions aarch64`. This is structural BTF inspection plus successful generation, not runtime BTF loading.

All 362 version entries, including each module_layout, match real kernel or combined external Module.symvers CRCs. All 358 undefined symbols are covered by those version tables. Every required symbol namespace is imported; codec and VCSM import DMA_BUF. Kernel/external export collisions are empty. VCSM resolves the real synchronous add and paired remove against built VCHIQ; the nonexistent registration name is absent. These modules retain external status and are diagnostic, unsigned artifacts; no loading or deployment compatibility is inferred.

| Module | SHA-256 | Bytes |
| --- | --- | --- |
| bcm2835-codec.ko | `466c379155b1eb0c59c7039a9c431d1aab8fabed913bb2c05f941f9802a404bd` | 1048968 |
| bcm2835-mmal-vchiq.ko | `1d8dc0b03f933ccfb722f453511c2ec0ec59b03b0fdbb19cf30d2a42c6f09ef3` | 652360 |
| vc-sm-cma.ko | `b3dbd61d4346ec455614fe7e4b7c4b893693939403a85f64dff4bfa8e78ab3d1` | 1084344 |
| vchiq.ko | `c2d79a9ce71feb2f65f20f6cc5cdce18ca668fc654d82f18fd7ee0392af3d878` | 1843920 |

The first post-build audit incorrectly included generated `.mod.c`/`.module-common.c` files when comparing the original 31-file source manifest. `final-audit-attempt1.py` and `final-audit-attempt1.log` preserve that audit failure. The corrected audit compares the original manifest's paths and separately authenticates the entire artifact copy; it passes. This was an evidence-check correction only, with no recompilation or source/header changes.

## Resource and storage handback

Both task containers used the pinned existing image with `--pull never`, no network, one CPU, jobs one, 768 MiB memory and memory-plus-swap (zero swap allowance), PID limit 64 and disk-backed storage. No VM setting, dependency installation, extra swap, privilege or device access was used. The actual build container elapsed 20.98 seconds; supervisor elapsed 25.59 seconds. `cgroup-after.log` records peak **805,306,368 bytes**, equal to the configured cap, with 761 memory-max events but zero OOM/kill events; this is cgroup memory including cache, not process RSS. Both final inspections report `OOMKilled=false`. No OOM or budget retry occurred.

`supervisor.jsonl` preserves five-second allocation checks with an 800,000,000-byte safe stop under the 1 GB new allocation ceiling and a 25-minute active cutoff. Its final stopped-container sample reports volume zero because exec is unavailable after exit; the final audit's read-only `du` measurement supersedes it: **199,172 KiB / 203,952,128 bytes** in the new Linux volume. New host copies include full source, generated objects/modules and whole evidence logs. `storage-final.json` records measured host/report allocation, both container writable deltas, shared image root size, retained historical charges and a finalization margin. The existing 4,483,140,434-byte image root is shared and is not charged again; each new writable layer is 196,608 bytes. Prior global 6.256 GB plus previous H.264 approximately 217 MB remains charged as 6.473 GB before this task, with no reset. This task's measured allocation is about 236 MB; adding a 1 MiB finalization margin leaves the cumulative estimate about 6.710 GB plus the parent's independently owned recovery allocation, below 15 GB under the supplied accounting. Host df observations are retained, but unrelated parent activity prevents attributing the whole filesystem delta to this lane. Docker metadata/log backing allocation is not independently measurable from SizeRw; the margin is an allowance, not a measurement.

`h264-combined-12-build` and `h264-combined-12-final-audit` are stopped. New Linux volume and host evidence remain retained. Only this new report and the new ignored evidence directory were written. No Pi/SSH/load/install, active kernel recipe, commit, staging, external message or subagent work occurred. The local heavy CPU lease is returned.

## Acceptance limits

This result accepts exact twelve-patch compilation and the recorded static artifact checks only. It does not accept full lifecycle safety, firmware capability/readiness, DMA cessation, working decode/encode, device/module/ancestor teardown, or ordinary initialization and error paths. Peer silence or missing RELEASED can still block lifetime progress indefinitely. The [quiescence contract](omarchy-pi-h264-quiescence-contract.md), real firmware response and mapping ownership, repeated decode/encode/close/reopen, physical recovery/rollback and separate destructive lifecycle qualification remain parent-owned gates. No deployment, performance, energy, Pi OS parity, 8GB or Pi 5 claim follows.
