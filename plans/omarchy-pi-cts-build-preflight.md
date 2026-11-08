# CTS 32.2 build preflight — 2026-11-08

Status: preparation guards corrected and locally control-tested; no compilation, container/VM access, installation, Pi/SSH, active sibling changes, staging, commits, external messages or subagents. Parent remains the sole physical/heavy-build owner. The ongoing Zstd validation uses the user-approved temporary 4 GiB OrbStack with CPU1; restoration to 2 GiB is pending with the parent. No claim of built archives, deployability or radio function is made.

## Lineage and exact config equivalence

Candidate root is `build/upstream-pi/stable-4.5/cts-kernel-candidate/`; paths below are relative to that root. Read AGENTS.md and all three requested kickoff/package/firmware plans. Compared every file in saved `../kernel-reviewed/recipe/` against `kernel/`: only PKGBUILD differs. Source lineage remains saved commit `db4db9894ddc11838724928846b134699a6108b3`, with reviewed private 7.3-32.1 as the base. Added CTS patch is unchanged, SHA256 `3d863fb62041f38ffd3f8428da69698053f6dae77a42bef03aac0633f0685c18`, final driver guard remains `2ae07906f5415ceec9e4cac92a0d2f503e3e28150f0f3cdf8115087b34df6fb1`. No H264, config, mitigation, LSM, compiler optimization or firmware source change.

Source config is exactly `41f89661b0af2c747e122f36417be7da2e7fb69049817c00404acf35fbef47a4`. Saved 32.1 `packages/resolved.config`, now copied to `kernel/reviewed-resolved.config`, is exactly `3b12d3dd8d8b0b24ab95ef96bb1b3388d2440a5bda069ecd74f3c7984a2fd51d`. The full diff is `kernel/preflight-evidence/source-vs-resolved.diff`. Differences are: insertion of Broadcom thermal section comments around BCM2711/BCM2835; relocation of disabled VIDEO_BCM2835_UNICAM into the generated Atmel section, disabled VIDEO_RASPBERRYPI_PISP_BE into the Raspberry Pi media section, and disabled SND_BCM2835_SOC_I2S into Broadcom; relocation of NVIDIA_FFA_EC before BCM_VIDEOCORE; relocation of BCM2835_POWER/RASPBERRYPI_POWER beneath Broadcom PM Domains. All 13,754 symbol/value pairs are identical, including explicit disabled symbols. No exception for changed CONFIG values is needed.

The original byte cmp would fail this already demonstrated olddefconfig result. `kernel/check-config.py` pins both baseline hashes and requires exact equality of every CONFIG symbol/value after parsing, rejecting added/missing/duplicate symbols and unrecognized noncomment lines. Only comments/order may differ. It runs in prepare before kernel compilation, again on the final resolved config, and during archive validation; headers must additionally be byte-identical to that actual resolved config. This preserves all architecture, toolchain, security and capability values, rather than checking only a selection. Current pinned compiler values include GCC 160101, LD 24600, Rust 109901 and pahole 132. Unknown future resolution differences fail closed; no toolchain drift allowance or newly generated defaults are presumed acceptable.

## Preparation changes and blockers

`build-offline.sh` requests CPU1; recipe build exports jobs1; runner and makepkg compression use one thread, NVIDIA compression explicitly uses `-T1`. Kernel module compression uses `ZSTD_NBTHREADS=1`: the actual cached 7.3 `scripts/Makefile.modinst` command is `$(ZSTD) --rm -f -q $<`, with no competing thread override. Compressed DWARF flags and all existing debug/BTF/security settings remain. Memory/swap caps, network-none, no pulls, named disk-backed volumes and parent-selected memory remain. The runner now rejects any existing candidate work volume rather than reusing one. It does not resize/restart OrbStack or release the parent's heavy-build lease.

`kernel/offline-inputs.sh` evaluates only the pinned recipe declarations and checks every source filename against recipe files/cache, then uses actual `pacman -T` for build and runtime dependencies. Both recipes are checked before cache copying/prepare; both source checksum/signature verifications run before the first compile. A fresh private GPG home imports only bundled keys and disables automatic retrieval. Normal makepkg checks remain; no syncdeps, dependency bypass or checksum/signature bypass was added.

File-only inspection finds the host `build/upstream-pi/linux-7.3.tar.xz`; saved reviewed evidence binds it to `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`. The host cache examined lacks `linux-7.3.tar.sign` and `NVIDIA-kernel-module-source-615.78.08.tar.xz`; the real source guard rejects both. The named read-only `omarchy-pi-kernel-reviewed-work:/downloads` cache was NOT inspected because container/VM access is excluded here. Prior successful signature verification in saved logs does not establish present cache completeness. Parent must inventory that actual cache and satisfy all sources without fetching/installing in the build run. NVIDIA has its original recipe checksums; no separate NVIDIA signature is declared. CTS patch provenance is the saved backport evidence, not a new upstream signature.

All three bundled ASCII key files were parsed with local GPG show-keys in disposable homes; primary fingerprints exactly match validpgpkeys: `ABAF11C65A2970B130ABE3C479BE3E4300411886`, `647F28654894E3BD457199BE38DBBDC86092693E`, `12D27D5D8C8E9BF1AABC7C7C7C64768D3DE334E7`. This is key-file identity checking, not a fresh cryptographic source-signature verification.

A further prerequisite is deliberately visible: firmware's unchanged recipe requires installed `linux-omarchy=7.3-32.2`, `raspberrypi-4-support`, python and util-linux when makepkg checks dependencies. A kernel archive in PKGDEST does not satisfy pacman's installed database. The saved image inventory predates 32.2 and cannot prove this requirement. Parent must reconcile the companion build environment/package dependency strategy before a full run; this lane neither installs packages nor silently disables checks. The new early dependency gate prevents discovering this only after an expensive kernel build. Current image presence, installed dependencies, volume free space, cgroup behavior and full patch replay remain unverified here. Host and work-volume guards require 40 GiB; parent owns capacity/memory coordination and the pending 2 GiB restoration.

## Archive checks and local evidence

`verify-packages.sh` accepts exactly the four expected nonempty archive filenames, validates name/version/aarch64 metadata, exact kernel/header/NVIDIA dependencies and capability, the normal five NVIDIA modules and their matching vermagic/signature metadata, Pi DTB/modules, BTF/DWARF, headers release/config/build files and AArch64 vmlinux. The existing broad driver checker is copied unchanged into `kernel/check-candidate-payload.py` and invoked with release `7.3.0-32.2-omarchy`; known configured absences remain visible. The unchanged firmware overlay/FDT verification still runs. These archive checks have NOT run on real 32.2 output because none exists. No old 32.1 archive was relabeled or replayed as candidate verification.

Original preparation scripts, PKGBUILD and original manifest were preserved BEFORE edits in `kernel/preflight-evidence/before/`. Full current recipe delta against saved 32.1 is `kernel/preflight-evidence/recipe-from-reviewed.patch`; the older top-level `kernel-from-reviewed.patch` and `manifest.json` remain historical preparation evidence. Their outdated jobs2/byte-cmp claims are superseded by this document.

`kernel/preflight-evidence/control-tests-3.log` records passing real config guards (saved config equivalence; comment/order variation; rejection of security, architecture, AUX capability, unknown, missing, duplicate and source-hash drift), real missing-source guard, unauthorized runner rejection before Docker, five shell syntax checks and key-file identities. Earlier full logs are retained: the first attempt hit Python decoding of macOS shell diagnostics; the second exposed macOS PATH lookup of `PKGBUILD` as `/usr/bin/pkgbuild`. Actual source calls now use `source ./PKGBUILD`; the final test uses existing GNU date for the trusted Linux recipe's timestamp declaration. No stub provides the behavior under test. Final minor runner aggregation/verifier arithmetic syntax is checked in `final-syntax.log`. Test source is retained as `control-tests.py`; run from repo root with `PYTHONDONTWRITEBYTECODE=1 python3 build/upstream-pi/stable-4.5/cts-kernel-candidate/kernel/preflight-evidence/control-tests.py > /tmp/cts-preflight-controls.log 2>&1`. The pacman dependency branch and real archive checks remain unexecuted on this Mac.

Only owned non-firmware INPUTS entries were changed/added; firmware entries and tested helper/recipe/hooks remain untouched. Complete file hashes, including preserved originals/evidence, are in INPUTS.sha256. Primary changed/added input hashes:

| File | SHA256 |
| --- | --- |
| `build-inside.sh` | `2418efa073c314e4e4005b75075db69c384fe8bfe32ff54cd7e20f98f76b2a8c` |
| `build-offline.sh` | `1d999ddf48648289b249eb55695fda044df88e94e56dfb126c6ce5a6502ec3a5` |
| `verify-packages.sh` | `a279215e853fabfdd624f019346cf9a20dee8cbc07f3fca552d7ce6af915ece1` |
| `kernel/PKGBUILD` | `638b3fb32cffbcab2ae2f07a4df0f3b081788aff61e76e2fb43e43214141db18` |
| `kernel/check-config.py` | `635e20e9e13b8193fe0df74c17d99c3ac783815a49e47b30fc137c1feb112ef1` |
| `kernel/offline-inputs.sh` | `40581d18eec881f3e03f1af6f1c5b23b60933fd5d0f69c0ceaded22514860e0e` |
| `kernel/reviewed-resolved.config` | `3b12d3dd8d8b0b24ab95ef96bb1b3388d2440a5bda069ecd74f3c7984a2fd51d` |
| `kernel/check-candidate-payload.py` | `2202245baca7b4d2b931c717fc2004b60a89116bbb17d2c8d052bba6e4f4f3b1` |
| `INPUTS.sha256` | `6be01e33ab0248bf1f9319c1138f12a06f262bc64917a4944f4c00a32fb23bb9` |

## Concrete parent command and physical limits

After the current heavy owner finishes, the parent resolves the actual offline cache/dependency prerequisites, chooses memory within the existing approved coordinated lane, and verifies storage. The current temporary 4 GiB VM is not a new permission request. With the existing 3482 MiB example selected by the parent, from repo root:

```bash
cd build/upstream-pi/stable-4.5/cts-kernel-candidate
CTS_BUILD_AUTHORIZED=parent-approved CTS_MEMORY_MIB=3482 bash build-offline.sh
```

Do not execute concurrently with Zstd; this lane did not execute it. A prerequisite failure must be read from the complete build-run.log; output/work/container evidence is retained and cannot be overwritten by rerunning. The runner's success is pending actual archive checks and exit/OOM/resource readback. There is no new permission gate and no build/deployability claim.

Preserve the firmware validation distinction: first install can return pacman 0 while its post-hook fails and the package remains installed. Explicit helper/media readback and no reboot are required; a successful package exit is insufficient. The parent already demonstrated same-version native root snapshot restore/reboot; do not repeat a permission gate for that completed rehearsal. Cross-version 32.2→32.1 kernel/DT/firmware rollback, physical FAT behavior, final FDT, CTS/radio operation and separate ESP/media recovery remain unqualified. Keep all holds and the original DMA path.
