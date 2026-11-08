# Reviewed CTS kernel config equivalence guard

This source-tested guard and both exact config inputs are preserved from the inactive CTS build preparation. It compares every symbol, including explicit disabled symbols, against the pinned 32.1 baseline. Only generated comments/order differ. Focused controls and original failures are under results/pi4-4gb-native/2026-11-08/cts-build-preflight/. No actual 32.2 build or archive acceptance is claimed. The matching kernel recipe and remaining offline build inputs remain separately controlled.
