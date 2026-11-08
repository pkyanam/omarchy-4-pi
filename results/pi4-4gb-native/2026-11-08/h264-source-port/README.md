# Inactive H.264 source port evidence

The first five source patches and production-function test sources are preserved under tools/pi-experiments/h264-port/. All four modules compiled and passed modpost/BTF against exact 7.3-32.1 headers, with genuine vermagic and no compiler warnings/unresolved symbols in the final logs. These are source/header build and host-boundary test results, not loaded modules or working decode.

The candidate is NONDEPLOYABLE. Connected-callback cancellation and command/worker ownership after successful close are implemented; complete service-close quiescence, failed-connect/remove/reprobe ownership, dma-buf generations and firmware RELEASED/DMA cessation remain unresolved. No package recipe references these patches.

Retained sanitizer tests 02–04 contain UBSan alignment errors despite printed PASS and zero exits: they are failed attempts. Final tests 05/06 disable sanitizer recovery and pass. The no-join mutant produces a production-worker ASan use-after-free, so the join test catches its intended race. Forty protocol IMPORT callers are not forty actual dma-buf imports. Callback tests use actual production functions but not real kernel/firmware execution.

All builds used the existing pinned kernel image, one CPU, 768 MiB total RAM+swap, disk-backed storage and make -j1. Later patches remain independently under implementation. Full ignored source/artifact trees are retained, while this snapshot survives a clean checkout. No Pi driver changes, performance, energy, 8GB/Pi 5 or hardware decode claim.

The tracked snapshot now includes service retirement 0006 (compiled) and source-tested 0007/0008 (not module-compiled). The earlier claimed OPENING requeue defect was disproven by actual queue_message/parser execution: CLOSESENT was already published by production code. The old stub-based progress-test02 PASS is INVALID and retained. Corrected real-body tests instead demonstrate and fix a failed-OPEN enqueue use leak. Peer response, firmware DMA and full per-generation lifetime remain separate gates.
