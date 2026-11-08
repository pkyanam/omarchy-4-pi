# CTS installed; pre-reboot verification passed

Actual target installation selected kernel/header7.3-32.11 and companion1-2; NVIDIA was absent and remains uninstalled. All transferred/root-staged hashes matched. Native update-prepare and actual identified-card extracted-payload preflight passed before transaction. Snapshot10 and complete independent old-module/UKI, ESP and firmware backups were verified onPi and off-board. Public-update holds now also include the companion.

Pacman exits0 and all11 independent checks pass: exact installed versions/new signed-module hash, installed-helper check, native update-verify, byte-exact overlay/config readback, only those two card files changed, unchanged EFI/NV bytes, no failed system units and taint0. UKI hash remains3b2b9760c87d373f7e8d6b85d718a720da777bc254c6592162cd24e160bf1d0a. The helper was verified directly, not inferred from pacman status.

This proves installation and pre-reboot consistency, not that the new driver or DT property is active. Live FDT is preserved before reboot. Encrypted-boot unlock availability has been requested; no reboot has yet been issued. Functional radio/peripheral, live FDT, physical FAT and rollback qualification remain open. NV-preserving unit tests and ALPM fixture are software evidence only, including the explicitly bounded subset fixture in the source report.
