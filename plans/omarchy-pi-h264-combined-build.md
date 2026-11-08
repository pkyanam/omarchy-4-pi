# Exact eleven-patch H.264 diagnostic build

November 8, 2026. **FAILED at a real source/API mismatch; NONDEPLOYABLE. CPU lease returned.** One external module compile attempt ran, with no source fix or compile retry. No `.ko` exists for this attempt. Four VCHIQ transport objects and their aggregate `vchiq.o` compiled; VCSM failed, so MMAL/codec, modpost, final modversions, namespace/domain validation, final vermagic and BTF were not reached. Earlier six-patch module hashes do not validate this series.

## Failure and smallest next fix

The whole retained [compile log](../build/upstream-pi/stable-4.5/h264-combined-11/compile.log) reports `vc_sm.c:1682`: implicit declaration of `vchiq_register_connected_callback`. The exact source has no declaration, definition or export under that name. Its patched header and transport instead declare, define and export `int vchiq_add_connected_callback_sync(struct vchiq_device *, void (*)(void))`. The smallest source correction to review separately is changing this one probe call to that existing synchronous registration API, retaining its return-value handling and paired removal. This correction was **not applied or compiled**; it cannot be claimed to clear any later errors. The same attempt warns that static `free_kernel_id` at line 237 is unused; that is separate cleanup to review, not the fatal error. [Line evidence](../build/upstream-pi/stable-4.5/h264-combined-11/failure-source-evidence.log) and [partial ELF/symbol output](../build/upstream-pi/stable-4.5/h264-combined-11/partial-abi-storage.log) retain the actual evidence.

The first preflight stopped before any compilation because its assertion expected 22,575 files under the kernel `build/` subtree, which contains 22,571 regular files; four regular package files are outside that subtree. `attempt1-*` and `preflight-attempt1.py` preserve that failed check. The corrected preflight authenticated all 22,575 regular archive files against the Linux clone, including case-sensitive names, before starting the sole compile. No source or kernel configuration workaround was introduced.

## Authenticated inputs and replay

Evidence root: `build/upstream-pi/stable-4.5/h264-combined-11/`. A fresh streamed narrow replay used the tracked existing helper, with zero fuzz, and matched all **30 C/header files plus the exact existing external Makefile** in `h264-port-candidate/replayed-import-11/`. Patches 0001–0011 matched the corresponding candidate patches byte-for-byte. Only the relevant Raspberry Pi source subtree was extracted; no full kernel extraction occurred. Existing sources, patches, passing/failed tests and historical reports were read-only.

- Linux archive SHA-256: `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`.
- Headers archive SHA-256: `1c90e860325eed52865869c060f762718784f9bda9cc9d7978fa636ce74f89e1`.
- Existing arm64 image: `sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2`.
- Compiler: GCC 16.1.1 20260430; GNU ld 2.46.0.
- Exact kernel release: `7.3.0-32.1-omarchy`. The private 32.11 repack's header payload identity is parent-supplied context, not a separately authenticated package comparison in this task.

[inputs-before.json](../build/upstream-pi/stable-4.5/h264-combined-11/inputs-before.json) and `inputs-after.json` pin both original archives, helper, series, Makefile and every patch and are equal. [series.json](../build/upstream-pi/stable-4.5/h264-combined-11/series.json) lists each ordered patch hash; its SHA-256 is `aa9f157a513c5d0109f2d64d29ed6d49b0d1d28e621e064f9226de7488daa085`. [source-before.json](../build/upstream-pi/stable-4.5/h264-combined-11/source-before.json) pins each exact C/header and Makefile; its SHA-256 is `7856f7649fd9ae3ef5812520463dda946dc9399f8ed2d327ffce251dc4c4d279`. These source bytes remained unchanged through compilation. [artifacts.json](../build/upstream-pi/stable-4.5/h264-combined-11/artifacts.json) records all partial generated file hashes. Aggregate **object**, not module, `vchiq.o` SHA-256 is `838d1a7f565e3bcddae70106e92aeb8c8649ee203acf21b5fe68dbd55823b3cb`. No final module hashes exist.

## Header and build contract

The original case-sensitive Linux headers were read only from `omarchy-pi-cts-intree-candidate-work:/work/headers`, mounted at `/input/headers`. The earlier Mac-extracted header trees were not used. A complete 184,572 KiB clone, authenticated against the archive, lives in new Linux volume `omarchy-pi-h264-combined-11-work:/headers`. Whole original/clone manifests before and after are preserved; both trees remained byte-identical, including symlink targets. `headers-changes.json` is empty. [verification.json](../build/upstream-pi/stable-4.5/h264-combined-11/verification.json) records these checks and the protected hashes:

| Input | SHA-256 |
| --- | --- |
| `.config` | `3b12d3dd8d8b0b24ab95ef96bb1b3388d2440a5bda069ecd74f3c7984a2fd51d` |
| `Module.symvers` | `9717ce5b1296bf82b456540fc72c7bb6609e0bfd4cd1049981b78a3232774c31` |
| `vmlinux` | `7ef2cbdc17b62649f168da6f8bf49ad2be8de4e85dc2556675ff4d279bae3a08` |

The unmodified external Makefile selects all four mutually dependent modules: VCHIQ, VCSM, MMAL and codec. Actual invocation: `make -C /work/headers/usr/lib/modules/7.3.0-32.1-omarchy/build M=/work/source -j1 modules`. Target config enables modules/unloading, MODVERSIONS, DWARF5 debug and BTF including modules. Nothing forced in-tree status, taint, vermagic, fabricated exports or modpost bypass. External outputs would be diagnostic and NONDEPLOYABLE even if linked. `environment.log`, `run.log`, `compile.exit` and `container-inspect.json` preserve execution/config details.

## Resources, storage and handback

All task containers used the pinned existing image, network disabled, one CPU (`cpu.max=100000 100000`), 768 MiB memory (`805306368` bytes), swap allowance zero and PID limit 64, using disk storage. No VM setting, pulls, dependencies, privileged mode or devices were used. The build container peaked at **510,640,128 bytes** cgroup memory; all OOM counters were zero and Docker `OOMKilled=false`. Build/preflight/final capture container elapsed about 20.4 seconds; `cgroup-after.log` records CPU/resource counters. No OOM retry or resource expansion occurred.

[storage-final.json](../build/upstream-pi/stable-4.5/h264-combined-11/storage-final.json) records measured allocation: Linux volume **193,466,368 bytes**, host evidence **21,368,832 bytes**, and all five new stopped container writable layers **983,040 bytes**, totaling **215,818,240 bytes** at that snapshot, plus a 1 MiB allowance for final report/manifests. The existing shared image is not charged again; its immutable root size and every new writable delta are recorded. The supplied prior conservative global charge of approximately 6.256 GB is retained, giving approximately **6.472 GB** including this snapshot, below 15 GB. No historical charge was reset and no evidence deleted. Host `df` observations are retained; unrelated parent activity means their whole-filesystem delta is not attributed to this task. Docker daemon metadata/log backing allocation is not independently measurable from `SizeRw`; the finalization allowance is a conservative margin, not a measurement of those bytes.

`supervisor.jsonl` records five-second storage checks and a 25-minute active cutoff, with an 800,000,000-byte safe-stop threshold under the 1 GB ceiling. Its stopped-container samples show volume zero because `docker exec du` is unavailable after exit; the independent read-only final volume measurement above supersedes those samples. All five task containers are stopped; the new case-sensitive volume and host source/object copies remain as evidence. The local heavy CPU lease is returned. No Pi/SSH/load/install, key access, active recipe edit, staging, commit, external message or subagent occurred. Only the new owned evidence directory and this new report were written.

## Remaining gates

A separately authorized minimal API correction and fresh exact-series combined build are still needed, followed by real modpost, modversion/namespace/ABI, BTF and target configuration checks. A successful compile would not resolve peer silence, reset/DMA quiescence, retained mappings, outstanding lifetime/error paths, module/device/ancestor teardown or working decode. The [quiescence contract](omarchy-pi-h264-quiescence-contract.md) and its remaining gates continue to apply: no timeout-to-free, CLOSE-as-RELEASED, fabricated cancellation acknowledgement or reset guarantee. Firmware capability/readiness and matching IMPORT/RELEASED, storage/physical recovery, repeated real decode/encode/close/reopen and separate destructive lifecycle qualification remain parent-owned. No deployment, performance, Pi OS parity, Pi 5 or 8GB claim follows.
