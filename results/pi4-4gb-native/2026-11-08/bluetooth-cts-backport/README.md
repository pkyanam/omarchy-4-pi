# Inactive upstream AUX hardware flow backport

Exact upstream driver hunks from ca576923c39863ac528427b563ea2f6631703d22 replay onto the saved Linux7.3 driver with no semantic adaptations, fuzz or offsets. The AUX-only DT overlay adds one property, uart-has-rtscts, to the verified PFTF route. All other captured FDT properties remain unchanged in offline application tests. No kernel/module/package build or installation has occurred.

The production-function harness records actual driver register writes at its modeled I/O boundary: unchanged source compiles and fails30 of62 checks; patched source passes62. These are source-boundary tests, not physical FIFO/radio/locking/resume results. Both driver and DT opt-in are required: applying the driver without the property changes fallback flow behavior and is not a qualified candidate for this board.

Source, overlay, replay/test helpers and pinned provenance are tracked under tools/pi-experiments/bluetooth-cts-backport/. The decision, primary sources and integration/rollback gates are in plans/omarchy-pi-bluetooth-cts-backport.md. A matching kernel/header and supported DT package pair is being prepared separately. The unrelated nondeployable H.264 port must not be bundled into this radio candidate.
