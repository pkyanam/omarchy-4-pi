# Private PFTF NV-preserving CTS companion

Normal makepkg source for companion1-2, exact kernel dependency7.3-32.11. All fixed firmware regions and complete FV/store headers are authenticated; only source-declared variable data may differ, and the helper never writes EFI. Source serialization proves the mutable start0x3b0064; no offset is guessed from observed changes.

The parent reviewed this implementation, passed actual extracted-archive target preflight and installed the coherent private candidate with verified backups. Target post-hook readback and native boot verification pass; physical reboot/radio/recovery qualification remains pending. Full tests/provenance/limitations: plans/omarchy-pi-cts-firmware-nv-preserving.md and results/pi4-4gb-native/2026-11-08/cts-installed-preboot/. Reproduction scripts retain original candidate mount paths; do not use as generic firmware installation instructions. No private firmware-variable contents or signing keys are tracked.

Migration from an already-installed old whole-file-baseline companion is not qualified. The tested target was a first install. This is not public EEPROM or firmware-variable update support.
