# Inactive CTS firmware transaction evidence

The parent reviewed the actual helper and full final helper/ALPM/verification logs. The helper has 25 passing tests, with preserved original-source failures; the actual private ALPM fixture proves dependency/removal/downgrade behavior and that a first-install post-hook failure can leave the package installed with pacman exit 0. This is an explicit stop/no-reboot state. No test was rerun merely for inspection.

Filesystem writes were real; mount/FAT facts were injected and media sentinels synthetic. No actual Pi/card operation or physical FAT durability/boot/radio/cross-version rollback result is claimed. See plans/omarchy-pi-cts-firmware-validation.md for complete tested boundaries. Containers remain stopped; sanitized resource facts are in resources.json.
