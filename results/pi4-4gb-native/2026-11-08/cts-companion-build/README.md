# CTS companion production archive build

Normal offline makepkg source/dependency checks and actual single-output split packaging produce the production companion archive SHA25647c5e4d4e8dc913730d5625235c1be9ca73e9b8eebb74d84fcb8cde2dfd1b139 (8069 bytes). Exact linux-omarchy=7.3-32.2 runtime dependency and support/python/util-linux dependencies remain. No target runtime packages were installed/faked in the production builder.

Parent read complete build/verify logs and checked the archive hash. Actual payload bytes and one-property saved-FDT delta pass; ALPM fixture preserves first-install post-hook failure with pacman exit0. Tiny offline build peak was65392640 bytes at .25CPU/128MiB/no-swap. No full kernel build, Pi install, physical FAT transaction, firmware boot or radio qualification follows. See plans/omarchy-pi-cts-companion-build.md. The full archive remains in ignored candidate storage; tracked source and reproduction remain under tools/pi-experiments/cts-firmware/.
