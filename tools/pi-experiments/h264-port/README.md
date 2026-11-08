# Inactive Linux 7.3 H.264 source port snapshot

NONDEPLOYABLE. No package recipe selects this series, and no module from it has been loaded on the Pi. This tracked snapshot preserves the first eight source patches and production-function tests beyond the ignored build tree. Patches 0001–0006 are module-compiled; 0007/0008 are source-tested only and await a combined module build. Later implementation remains separately owned and unqualified.

Patches 0001–0003 port pinned Raspberry Pi VCSM/MMAL/bcm2835-codec to upstream Linux 7.3; 0004 synchronizes deferred callback cancellation; 0005 adds command ownership and actual SMIO worker join after successful service close. Upstream platform/transport/media architecture remains. Copyright/SPDX headers and the underlying Linux/downstream license terms are retained in the patch contents. Complete source provenance is in reference-provenance.json. Do not treat compile success as safe lifecycle, successful DMA or decoding support.

Use the exact Linux archive (SHA-256 87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953), then replay into a new directory:

```bash
python3 tools/pi-experiments/h264-port/replay-source.py --archive /absolute/path/linux-7.3.tar.xz --output /absolute/path/new-source
```

The parent ran this tracked wrapper once and compared every extracted/patched C/header file with the final five-patch compiled replay; all matched. The external Makefile prefers patched transport headers and builds the four mutually dependent modules together. With exact kernel headers archive SHA-256 1c90e860325eed52865869c060f762718784f9bda9cc9d7978fa636ce74f89e1 extracted to private build storage, compile inside the existing pinned Linux arm64 image using `make -C /headers/usr/lib/modules/7.3.0-32.1-omarchy/build M=/absolute/path/new-source -j1 modules`. Keep one CPU, 768 MiB total RAM+swap, disk-backed storage and no network; this is a compile procedure, not an install payload. Rebuilt module byte equality is not asserted.

Production-function checks use the actual replay source and pthread/transport boundary shims. Pass an absolute replay path so copied test scripts are independent of source placement:

```bash
python3 tools/pi-experiments/h264-port/lifecycle-unit/tests/run.py /absolute/path/new-source
python3 tools/pi-experiments/h264-port/smio-unit/run.py /absolute/path/new-source
```

These scripts compile small host sanitizer executables; generated files are narrowly ignored. Original passing and deliberately failing mutant logs, along with final module compilation evidence, are tracked in results/pi4-4gb-native/2026-11-08/h264-source-port/. Do not rerun unchanged coverage merely to inspect its output. The unit READMEs describe the exact tested boundaries and retained failed attempts; their original candidate-relative artifact paths refer to the ignored research workspace.

Full lifecycle remains incomplete: interrupted service-close completion, failed-connect/remove/reprobe, immutable dma-buf generation/device/module ownership, and firmware RELEASED/DMA quiescence. Service close and host worker join alone do not prove firmware stopped accessing memory. The separate invalid-handle MMAL fix is now included as 0008, with source tests but no module compile yet. No driver performance, energy, Pi OS parity, 8GB or Pi 5 qualification follows.

## Service retirement and actual protocol correction

0006 adds opt-in owner-pinned service retirement/final-reference completion and integrates it into SMIO stop/init unwind. Its production-function tests and all-module compile pass. Its historical report contains an OPENING-progress hypothesis later disproven by full production queue/parser tests; read progress-unit/README.md as the correction. Actual queue_message publishes CLOSESENT, so no speculative requeue patch is included.

0007 instead fixes the demonstrated failed-OPEN-enqueue use leak and lets an owned service retire locally only when OPEN was never published. Corrected production queue/parser/sync/close tests pass and fail on the preceding six-patch source for the intended use-leak assertion. An earlier test pass with a stub omitting CLOSESENT is retained as INVALID evidence. 0008 is the unchanged independently tested MMAL follow-up. The tracked eight-patch replay matches all thirty C/header files of the final source-tested candidate. Neither new patch is module-compiled yet; do not reuse six-patch module hashes for them.

close-unit and progress-unit retain their production-body test generators and boundary sources. Copy the research snapshot into private disk-backed test storage before running generators that emit beside their source. Pass absolute replay/output paths to their run.py scripts. Source state machines execute with injected platform/peer boundaries; real firmware, scheduler/RCU, dma-buf generations and DMA cessation remain unqualified.
