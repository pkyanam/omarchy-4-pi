# Prompt for an embedded engineering agent

Continue the native Omarchy Raspberry Pi integration. Read `plans/omarchy-pi-release-quirks.md` first, then the evidence under `build/upstream-pi/stable-4.5/`. This is the upstream UEFI/Limine candidate, distinct from the published community U-Boot image.

Work in the sibling repos `omarchy-upstream-pi` (upstream review), `omarchy-upstream-pi-stable` (installed 4.5 lineage), `omarchy-pkgs-pi` and `omarchy-iso-pi`. The physical board is a Pi 4 4GB, revision c03115, with uncapped RAM, PFTF 1.53 Device Tree firmware, a required mainline-DMA overlay, and an encrypted Btrfs USB SSD. Prioritize HDMI EDID/ELD and no-signal wake, Bluetooth UART/clock routing, media-driver coverage, and genuine package upgrade/reboot/rollback validation. Preserve the normal upstream updater and package capability checks.

Distinguish tested fixes from hypotheses. Use matching kernel sources/headers; preserve firmware and ESP recovery copies. Do not invent EDID, copy foreign kernel modules, disable features to hide gaps, or impose speculative tuning. The owner is asleep: retain authorized credentials, ask no questions, and do not wake the display or reboot. Headless investigation/builds may continue. Defer physical acceptance until the owner returns. Update the ledger with evidence and keep commits atomic. Stop before pushing or opening PRs.
