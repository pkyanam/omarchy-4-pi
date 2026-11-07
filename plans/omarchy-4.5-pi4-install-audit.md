# Omarchy 4.5 Pi 4 install and upgrade audit

Audit date: 2026-11-06. Target: Raspberry Pi 4 Model B, 4GB and 8GB, stock clocks. Pi 5 is future scope. This is the research report for the parent [upgrade plan](omarchy-4.5-pi4.md), not an implementation or release approval.

## Scope and evidence boundary

The audited baseline is `393f48c3cd6e32e36111064fa99d2f59e4449aa5`, which is also the `v0.2.0-alpha.4` tag. The original general-release image is `v0.1.0-rc.1`, commit `bd0e85fc81879c8d7053cd4de540cced5a43988a`. The parent's upstream fetch became available during this audit: `upstream-v4.5.0` peels to `ac2690cd7be4f47e4a255f5e2e78d904d436b068`. I did not repeat that fetch.

I read `AGENTS.md`, the install-scripts, migrations, command-metadata, acceptance-tests, and visual-verification task guides, and the testing, update-process, Pi install, performance, upgrade, and release documentation. The audit covers `install-rpi4.sh`, `build-packages-rpi4.sh`, every `image/` helper, the update commands, relevant migration transitions, and owner/first-login provisioning. Technical sources below are upstream source, official package metadata, and the port's published manifests.

No implementation file was changed. No real installer, real update, package build, image build, host-tool installation, commit, push, merge, or publication was performed. Tests executed installed code only with temporary homes, mounted-root substitutes, or stubbed system operations. No Pi or running Linux desktop was available to this audit, and no hardware, boot, compositor, thermal, audio, or SSH acceptance is claimed.

**Assessment:** retain the existing Pi safeguards, but do not describe a 4.5 source import as an end-to-end upgrade yet. Package availability and migration closure are the main functional blocker. Published alpha4 provenance is malformed JSON. Additional failure-reporting, build-integrity, first-boot, and factory-workspace defects need focused repairs and regression gates.

## Existing safeguards that must survive the upgrade

- The direct installer rejects root, non-`aarch64`, missing pacman/sudo, and a non-Pi-4 model unless the explicit unsupported-hardware override is used (`install-rpi4.sh:102–117`).
- The ARM repository profile pins `Architecture = aarch64`, requires package signatures, and keeps the ALARM kernel/firmware/U-Boot path. Pi package preparation removes the Limine dependencies and boot configuration entries (`build-packages-rpi4.sh:19–23,46–75`). The [official ALARM AArch64 instructions](https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4) describe mainline Linux and U-Boot, which is the relevant boot contract.
- Recipe lookup defaults to an exact reviewed commit, refuses dirty or unexpected cached recipe origins, and supports a persistent source cache (`install-rpi4.sh:132–159`). Package staging excludes image artifacts and Git history (`build-packages-rpi4.sh:63–75`).
- The current update guard checks architecture, source origin, `main`, `origin/main`, a completely clean checkout, repository names, and obvious upstream/x86 mirror mistakes (`bin/omarchy-update-rpi4-guard:11–45`). Source updates use a fast-forward and a separate installed-source receipt, making a failed package installation retryable after Git advances (`bin/omarchy-update-rpi4:30–73`).
- First boot orders root expansion before owner provisioning and owner provisioning before SDDM, with `Requires=` as well as `After=`. Grow failure retains its retry marker. Hostname assignment and readback precede account/SSH setup; Avahi waits for owner provisioning. Credentials are staged privately and validated rather than executing Imager-supplied shell commands.
- The factory verifies the base's signature against a fixed signer, uses a private mount namespace, checks initramfs generation explicitly, runs the actual ARM Hyprland config parser as a non-root user, scrubs factory accounts/SSH identity, audits the assembled root, and performs offline filesystem checks before compression.
- Pi build/log/zram/writeback/oomd defaults are independent of the upstream recipe's broad `aarch64` exclusions. The clock guard remains opt-in; stock images reject applied clock/thermal overrides. Do not remove these because upstream now advertises ARM support.

The default image is ext4. There is no automatic, bootable pre-update rollback snapshot. The documentation already tells users to back up the card. Preserve that distinction from upstream's Limine/Btrfs recovery model.

## End-to-end path traces

### Fresh image

1. `image/build-rpi4-image.sh` enters a private mount namespace, requires root/native AArch64 Linux, validates the 12 GiB image-size floor, downloads the ALARM rootfs/signature, and verifies the expected signer (`46–97,185–205`).
2. It creates a 1 GiB FAT boot partition and an ext4 root partition, mounts by labels, binds `/dev`, `/proc`, `/sys`, and disk-backed package work/cache storage (`234–298`). It creates a shallow source checkout plus tracking branch and overlays the supplied source tree (`300–342`).
3. A temporary unprivileged builder runs `install-rpi4.sh --image --minimal`. The installer refreshes ALARM packages, selects available base-list packages, builds six required recipes, builds/installs the four local core packages, records `/etc/omarchy-rpi4.conf`, and applies system/hardware setup (`install-rpi4.sh:414–425`).
4. Image provisioning stages an ARM64 Node tarball and enables the grow/owner dependency chain. Factory cleanup removes accounts/identity and writes the manifest/installed-source receipt, runs the rootfs audit and offline filesystem checks, then compresses and creates Imager catalogs (`image/build-rpi4-image.sh:493–574`).
5. First boot expands the discovered root partition, then consumes complete valid Imager settings or runs the HDMI form. Owner setup applies hostname, creates or resumes the account, installs keys/network/SSH/login settings, finalizes the user, removes provisioning state, and releases SDDM (`bin/omarchy-provision-owner:1121–1306`).
6. The first graphical login runs `omarchy-provision-first-run`, which attempts finalization again, installs hooks, starts user units, and marks first-run completion if its tracked steps succeed (`bin/omarchy-provision-first-run:39–99`). The finalization attempt itself is outside that failure accounting; see F4.

Direct installation into an existing ALARM user's system uses the same package path but calls `omarchy-reinstall-configs` and finalizes the current user immediately. It does not have the factory's protected, disk-backed work mounts. See F10 and F11.

### Original RC1 to new sources

The published RC1 updater is materially older than the current one. It fetches and fast-forwards the checkout, invokes the builder without reconciling recipe/runtime prerequisites, and treats an already-current Git HEAD as an already-installed core. The image factory's recipe checkout was temporary and need not exist in the owner's home. If the first rebuild fails after Git advances, a second ordinary update can skip it and report the core current. RC1 also lacks `ttfx` and the later performance defaults.

The [documented one-time bootstrap](../docs/pi-upgrade.md) correctly bypasses that old installed updater: validate the canonical source checkout, fetch/fast-forward, prepend its `bin/`, set two-job build budgets, and invoke the current source updater. Its existing fixture covers eight preflight/handoff cases. That is a necessary handoff, not proof of a complete upgrade: missing ARM migration packages still stop the migration queue (F1).

Do not run `install-rpi4.sh` again as an upgrade shortcut. It would replay repository replacement, destructive default seeding, and first-install semantics. Do not use `omarchy-upgrade-to-quattro`; it explicitly rejects AArch64/Pi and owns the older x86 package-layout transition.

### Alpha4/current updater to new sources

The current top-level order is preflight → transcript/update lock → free-space check → confirmation/cache pruning/snapshot attempt → stay-awake → Pi source fetch/rebuild → ARM keyring refresh → ALARM full system upgrade → per-user migrations → hooks/AUR/mise/orphan cleanup → status/restart (`bin/omarchy-update:11–69`).

The Pi core updater checks `/var/lib/omarchy/rpi4-source-commit`; if it differs from source HEAD it runs only `ensure_package_sources` and `install_arm_packages` in minimal mode, builds the four core packages, installs them, reapplies Pi performance drop-ins, reloads systemd, and records the source commit. It never runs `install_official_packages`, owner provisioning, or config reset. That protects identity and customization, but does not establish the new release's complete package set. Required locally built packages are only checked for presence, not version.

Migrations run sequentially under `bash -euo pipefail`, and only successful scripts receive per-user markers (`bin/omarchy-migrate:88–97`). This is correct and fixture-tested. A missing package in an earlier migration blocks all later migrations; it must be solved by providing the package or a deliberate Pi-compatible behavior, not by touching all migration markers.

The receipt means **core source successfully installed**, not **the complete update succeeded**. Keep it separate from migration state and an eventual overall-update result. A failed later system upgrade or migration must still be retried even when the core receipt is current.

## Verified package and published-image observations

The [RC1 manifest](https://github.com/pkyanam/omarchy-4-pi/releases/download/v0.1.0-rc.1/omarchy-4-pi-20260904-bd0e85fc-minimal.manifest.json) is valid JSON. The [alpha4 manifest](https://github.com/pkyanam/omarchy-4-pi/releases/download/v0.2.0-alpha.4/omarchy-4-pi-20260923-393f48c3-minimal.manifest.json) fails strict JSON parsing; its inventory below was read with a permissive parser solely to diagnose the defect, not to validate the artifact.

| Item | Published RC1 | Published alpha4 |
| --- | --- | --- |
| Port source | `bd0e85fc…` | `393f48c3…` |
| Recipe commit | `99234a4fbb61b46225b2e9e560e114fbfebe8a95` | Same |
| `omarchy`, `omarchy-settings` | Both `4.0.2-1` | Both `4.0.2-1` |
| Hyprland | `0.56.1-3` | `0.56.2-3` |
| Quickshell | `0.3.1-1` | `0.3.1-1` |
| `linux-aarch64` | `7.2.2-2` | `7.2.6-1` |
| `ttfx` | Absent | `0.3.2-1` |
| `omasnap`, `owe`, `owe-lockfeed`, `elsewhen` | All absent | All absent |
| Inventory entries | 906 | 904 |

The release API lists RC1's compressed image at 2,081,221,712 bytes and alpha4's at 2,096,556,160 bytes. Both fit the current split threshold of 2,139,095,040 bytes (2040 MiB), but alpha4 has only about 40.6 MiB of headroom under that threshold. This makes F8 relevant to a larger 4.5 image without predicting its eventual size. Sources: [RC1 release API](https://api.github.com/repos/pkyanam/omarchy-4-pi/releases/tags/v0.1.0-rc.1), [alpha4 release API](https://api.github.com/repos/pkyanam/omarchy-4-pi/releases/tags/v0.2.0-alpha.4).

I inspected the four official ALARM repository databases over HTTPS, in memory, with at most two concurrent requests and a 32 MiB cap per response. This was inventory research, not package-signature verification or installation. These rolling databases can change; hashes identify the exact observations.

| Repository | Bytes | SHA-256 of inspected `.db` |
| --- | ---: | --- |
| [core](https://fl.us.mirror.archlinuxarm.org/aarch64/core/core.db) | 256755 | `dc25e41ac254b6e224968bf7a942b8f1bd87e46f0ddf4aec9130bbdc894d7237` |
| [extra](https://fl.us.mirror.archlinuxarm.org/aarch64/extra/extra.db) | 10755740 | `941ea3f053bf61bd7d67dca41420629bb77caecbd686a8321e2518ef969bfd45` |
| [alarm](https://fl.us.mirror.archlinuxarm.org/aarch64/alarm/alarm.db) | 62232 | `c6a89b81544bfc6596b47a37e63abe9e36570445385193f6f3b37403d14887a0` |
| [aur](https://fl.us.mirror.archlinuxarm.org/aarch64/aur/aur.db) | 10556 | `263b04baaf9e27f6bc7840455a2bf65bf9b7f9cad0be5efce0ca3650eb634024` |

At inspection, none contained `omasnap`, `owe`, `owe-lockfeed`, `elsewhen`, `ttfx`, `monologue`, `hype`, `disktree-bin`, `omarchy-hyprland-titlebars`, `omarchy-power-profiles-daemon`, `gliff`, or `signed`. ALARM's binary repository named `[aur]` is not a general fallback to all AUR recipes. `omarchy-pkg-add` only invokes pacman; it does not build those recipes.

The observed repositories did contain `linux-aarch64 7.3.1-2`, `hyprland 0.57.1-1`, `quickshell 0.3.2-1`, `firmware-raspberrypi 20260311-1`, `cloud-guest-utils 0.34-1`, `zram-generator 1.2.1-1`, and the four named Fcitx input-method packages. A new rolling image therefore exercises a different kernel/compositor/library set from the published September images. Existing fixture passes and historical boot reports cannot establish compatibility of that set.

## Prioritized findings and concrete repairs

Priority meanings: **P1** blocks a complete, trustworthy 4.5 image/upgrade or exposes a destructive path; **P2** is a maintenance/recovery defect to address or explicitly bound before release. “Verified” means observed source/artifact/fixture behavior; hardware consequences remain unverified unless stated otherwise.

### F1 — P1: package selection silently omits runtime features, while migrations demand them

**Verified evidence:** `install-rpi4.sh:170–209` silently skips every non-excluded base-list package for which `pacman -Si` fails. `261–294` builds only six required recipes plus ten optional ones; the absent runtime packages above, apart from `ttfx`, are not supplied there. `bin/omarchy-update-rpi4:49–55` does not call the official-package reconciler. The mounted-root audit's package list (`image/audit-rpi4-rootfs.sh:268–274`) does not require Omasnap/OWE or verify the user units' backing packages. The published manifests confirm those omissions in both images.

For RC1, `migrations/1788129995.sh:3` demands `omasnap`, `1789764927.sh:3` demands `owe owe-lockfeed`, and `1790042972.sh:3` demands `elsewhen`. A fixture ran the real migrator and real package helper against a stubbed missing `omasnap`: exit 1, no completion markers, no later migration. This demonstrates correct fail-closed migration behavior and an unresolved package-supply requirement.

The 4.5 import adds more unconditional or relevant requests: [Disktree](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/migrations/1791345484.sh#L3), [titlebars](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/migrations/1791403310.sh#L3), [Omarchy's power-profiles-daemon replacement](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/migrations/1791554699.sh#L6), and [Gliff on AArch64](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/migrations/1792041364.sh#L3). Minimal mode does not prevent migrations from requesting these. The existing `power-profiles-daemon` install makes its replacement migration relevant to Pi, despite the migration's ARM-laptop rationale.

**Proposed repair:** define one explicit Pi package contract with required desktop/runtime dependencies, optional applications, and unsupported features. Fail the preflight on unresolved required packages rather than silently skipping them. Supply reviewed ARM recipes/artifacts or an explicit supported replacement for each required migration dependency. Reconcile that contract during updates as well as fresh installs. An optional feature may be disabled deliberately with corresponding menu/unit/config changes, but its migration must not falsely claim the feature installed. Preserve existing capture/edit functionality until its replacement is installed and verified.

**Regression gates:** missing required package fails before core installation; optional omission is recorded; both RC1 and alpha4 migration sets finish with no unresolved package request; a fresh minimal image's enabled user units all have installed executable dependencies. Test absence of OWE, Omasnap, titlebars, and the daemon replacement individually.

### F2 — P1 for the installed base: RC1 can strand a failed rebuild behind an advanced Git HEAD

**Verified evidence:** [RC1's updater](https://github.com/pkyanam/omarchy-4-pi/blob/bd0e85fc81879c8d7053cd4de540cced5a43988a/bin/omarchy-update-rpi4#L29) checks only whether source commits are behind, then merges before building. It has neither the installed-source receipt nor prerequisite reconciliation. A fixture with HEAD already advanced reproduced exit 0 and the message that the core is up to date, without invoking the failing builder. The current receipt-based implementation fixes that class of retry once users actually enter it.

**Proposed repair:** retain and test the explicit current-source bootstrap for RC1. Make the 4.5 upgrade instructions start with installation-generation detection and route RC1 through that bootstrap. Resolve F1 and establish reviewed recipes before asking existing users to run it. Do not infer installed packages from source HEAD or remove the current retry receipt.

**Regression gates:** simulate failure after merge but before build, during each package build, and during `pacman -U`; retry must install the target packages and only then advance the receipt. Run the documented bootstrap against an untouched clone of each published image, including one without any recipe cache. Hardware verification of this entire path is still outstanding.

### F3 — P1 for release provenance: the published alpha4 manifest is invalid JSON

**Verified evidence:** `image/build-rpi4-image.sh:432–449`, especially line 440, inserts all matching mirror `Server` values into a JSON string without encoding. `default/pacman/mirrorlist-rpi4-image:6–8` contains three `Server` lines. The published alpha4 manifest fails strict parsing at line 8, column 68 because the resulting string contains literal newlines. The real manifest writer was also executed as an isolated fixture: it returned 0, wrote an installed-core receipt, and produced the same strict-JSON error.

The mounted-root audit uses grep/sed to inspect the manifest (`image/audit-rpi4-rootfs.sh:295–365`); it never parses the complete JSON document. Its otherwise useful inventory checks therefore miss this defect. The existing rootfs fixture suite passes while the published manifest remains invalid.

**Proposed repair:** generate the manifest through a JSON encoder and represent mirrors as an array. Validate the complete schema with a strict parser before recording the installed-core receipt, auditing, copying artifacts, or compression. Check source/recipe identity, exact inventory, and Node hash from parsed values. Also validate any configurable URLs through the encoder instead of relying on quote-only checks.

**Regression gates:** use the current three-server mirrorlist plus URLs with characters that require JSON escaping; assert strict parse, schema, and inventory equality. Parse the embedded and downloadable manifests and compare them byte-for-byte. Do not silently replace the already-published alpha4 artifact in this initial audit.

### F4 — P1: failed user finalization can still complete unattended owner setup and first-run

**Verified evidence:** `bin/omarchy-provision-owner:1137–1140` intentionally converts a failed finalizer into a warning flag and continues. `cleanup_oem_state` removes `pending`, staged credentials, and the setup user marker (`1105–1116`). The interactive path displays a retry warning (`1212–1218`); `run_imager_setup` ends successfully without checking that warning (`1229–1256`). A stubbed finalizer returning 23 produced worker exit 0, a warning flag, and removal of the pending marker.

At first login, `bin/omarchy-provision-first-run:46` ignores finalization failure. That attempt does not set `first_run_failed`, so otherwise-successful steps mark `first-run-user` at line 96. A fixture returned 23 from `omarchy-provision-user` and still observed exit 0 plus that completion mark. Subsequent logins hit the early completion gate and do not automatically retry the finalizer. The existing first-run test covers only the already-complete gate.

**Proposed repair:** decide which finalization leaves are necessary for a usable account and keep their failures pending; record optional, offline-deferred work separately. At minimum, include finalization in first-run failure accounting and surface unattended warnings persistently. Successful account creation need not be undone, but it must not imply all runtime setup succeeded. Keep the pinned-user resume behavior and do not rerun owner creation just to retry per-user setup.

**Regression gates:** fail Node staging/unpack, user theme/default setup, and a required leaf in both HDMI and Imager paths; verify the intended pending/retry markers and visible diagnostics across a reboot and two logins. An offline deferred task must not disappear behind a first-run completion marker.

### F5 — P1: core packaging disables the pinned source-integrity checks

**Verified evidence:** `build-packages-rpi4.sh:109–113` invokes `makepkg --nodeps --skipinteg` for all four packages. The [pinned font recipe](https://github.com/omacom/omarchy-pkgs/blob/99234a4fbb61b46225b2e9e560e114fbfebe8a95/pkgbuilds/ttf-jetbrains-mono-nerd-basic/PKGBUILD#L13) downloads a remote font archive and declares its SHA-256. That checksum is bypassed by this invocation. Pinning the recipe Git commit does not authenticate a downloaded archive or a modified cached copy. The local `OMARCHY_SRC` branch of the two core recipes already uses empty source/checksum arrays, so it does not need a blanket integrity bypass. [Official makepkg options](https://man.archlinux.org/man/makepkg.8.en) document what these flags disable.

**Proposed repair:** remove the global integrity bypass and allow makepkg to check each downloaded payload. If a local-source recipe requires adaptation, scope it to that local input rather than every package. Keep the official font license in the package. Review any intentional `--nodeps` use against a fully resolved dependency set rather than treating it as a dependency-reconciliation mechanism.

**Regression gate:** a cached font archive with one modified byte must fail before package output or receipt changes; a normal pinned download must verify. This audit did not download or build the font archive.

### F6 — P1 for a credible 4.5 upgrade: package identities and local runtime versions are stale

**Verified evidence:** `image/omarchy-pkgs.commit:1` pins `99234a4f…`. Its [omarchy recipe](https://github.com/omacom/omarchy-pkgs/blob/99234a4fbb61b46225b2e9e560e114fbfebe8a95/pkgbuilds/omarchy/PKGBUILD#L12) and [settings recipe](https://github.com/omacom/omarchy-pkgs/blob/99234a4fbb61b46225b2e9e560e114fbfebe8a95/pkgbuilds/omarchy-settings/PKGBUILD#L12) declare `pkgver=4.0.2`, `pkgrel=1`; the builder supplies new local source without changing those fields. Both published image manifests record those same versions even though their source differs. `omarchy-version` reports pacman package metadata, not the checkout's `version` text (`bin/omarchy-version:20–28`). The upstream 4.5 tag also retains `4.0.0.alpha` in that text file, so editing it alone is insufficient.

`install-rpi4.sh:284–293` builds a required/optional recipe only when `pacman -Q` says its name is absent. A fixture in which all six required names were present invoked no rebuild, regardless of installed version. The core receipt can then advance while required runtime packages remain older than the reviewed recipe pin. Default core rebuilding refreshes four packages; it does not refresh all six required recipes. AUR updates are a separate, later supply path and do not establish the reviewed versions.

**Proposed repair:** choose a monotonic, documented Pi package version/release scheme representing upstream 4.5 plus port revision, with identical core/settings versions and exact provenance. Move the reviewed recipe pin only after inspecting its ARM dependencies and installed paths. Compare installed runtime versions against that reviewed contract and rebuild/update when needed. Store enough package/version information alongside the source receipt to diagnose drift; a same-name package must not automatically satisfy a changed requirement.

**Regression gates:** pacman sees an upgrade from both published `4.0.2-1` installs; `omarchy-version` and the manifests identify the intended release; recipe-only/runtime-version changes are applied; unchanged successful packages skip unnecessary rebuilds. Test the full tuple of source, recipe commit, installed package versions, and migration state rather than Git HEAD alone.

### F7 — P1 destructive path: a caller-provided image workspace is recursively deleted

**Verified evidence:** `image/build-rpi4-image.sh:581–587` accepts an existing `OMARCHY_IMAGE_WORK` directory and arms `cleanup`. `cleanup:178–179` recursively deletes the entire directory by default, with no ownership marker or requirement that it be a fresh factory-created child. A safe fixture placed an unrelated sentinel in its own temporary caller directory and executed only the actual cleanup leaf with empty mount/device variables: the sentinel and directory were deleted. The help describes this as a reusable work directory (`38–40`).

**Proposed repair:** canonicalize a dedicated workspace parent and create a unique factory-owned child beneath it. Delete only that child after checking a sentinel containing the expected build identity. Reject dangerous/overlapping root, repository, output, home, and symlink paths before any download or mount. Treat `--keep-work` as retention of owned temporary state, not as the only protection for caller content.

**Regression gates:** pre-existing unrelated files survive success, early failure, and interrupted cleanup; root/repository/output overlap is rejected; cleanup never traverses a supplied symlink. Perform these tests only in throwaway fixture directories.

### F8 — conditional P1 for an oversized release: split assets leave a broken Imager catalog

**Verified evidence:** `image/prepare-release-assets.sh:42–54` omits the whole `.img.xz` when it exceeds the part threshold and emits numbered parts. The workflow then copies and uploads the existing catalogs unchanged (`.github/workflows/build-rpi4-image.yml:104–109`), whose URL still names the missing whole-image asset. Catalog validation checks syntax/schema, not asset existence (`image/validate-imager-catalog.sh:99–101`). A tiny valid archive with a 1 MiB fixture threshold produced two parts, no whole image, and a catalog that still passed validation while pointing at that absent file.

The generated reassembly instructions recommend “Use custom” (`prepare-release-assets.sh:70–71`), which discards the catalog customization metadata needed for Imager owner/Wi-Fi/SSH settings. The port already provides local-catalog helpers that avoid this problem. See the [official customization contract](https://github.com/raspberrypi/rpi-imager/blob/v2.0.11.1/doc/os_customisation_formats.md) and the port's `docs/raspberry-pi-4.md:107–113`.

**Proposed repair:** either ensure the downloadable complete image is hosted at the catalog URL or avoid publishing a catalog that promises an unavailable whole-image download. For reassembly, point users to the existing local-manifest/macOS catalog workflow so customization remains available. Validate the release asset list against every catalog URL before publication.

**Regression gates:** exercise both direct and forced-split paths, reassemble and verify compressed/extracted hashes, and prove the customizations are offered through the documented workflow. Neither currently published image requires splitting, so do not describe their existing links as broken.

### F9 — P1 false-success path: AUR update failure returns success

**Verified evidence:** `bin/omarchy-update-aur-pkgs:12–20` has no errexit and runs `echo` after `yay -Sua`. A fixture with accessible AUR, foreign packages, and `yay` exiting 42 returned 0 from the real helper. The outer update's `set -e` cannot catch a child that returns success; the sequence test stubs the whole helper and does not cover this internal failure.

**Proposed repair:** propagate the AUR command's status explicitly or adopt strict failure handling with a deliberate policy for genuinely optional/offline updates. If skipping is supported, report that result separately from successful completion. Keep the Pi core package ignore list.

**Regression gate:** make `yay` fail with a nonzero status and assert that the update stops or reports a clearly defined partial result before the normal success/restart path. Also test unreachable AUR and a successful/no-op update.

### F10 — P2 destructive direct-install path: existing user configuration is overwritten without a separate opt-in

**Verified evidence:** normal `install-rpi4.sh` unconditionally calls `seed_user_defaults` (`324–327,424`), which invokes `omarchy-reinstall-configs`. That command explicitly identifies itself as destructive and runs `cp -af /etc/skel/. ~/` (`bin/omarchy-reinstall-configs:3,14–19`). This also copies migration markers, potentially making an attempted repair/reinstall look freshly migrated. Repository configuration is similarly replaced without backup (`install-rpi4.sh:119–129`). These are installation semantics, not a safe existing-image upgrade.

**Proposed repair:** reject an already provisioned Pi unless the operator explicitly chooses a repair/reset mode, or require a distinct reset-defaults option with an exact affected-path preview and backup. Keep normal upgrades on the package/migration path. Preserve administrator pacman settings through a reviewed reconciliation rather than broad replacement during repair.

**Regression gates:** a second installer invocation refuses before mutations; custom hostname/display/home files and migration markers survive a normal upgrade; an explicitly selected reset has a usable backup and clearly documented scope.

### F11 — P1 for the 4GB target: conservative build settings arrive after initial compilation

**Verified source ordering:** the direct installer builds its required recipes and four core packages at `420–422`; `omarchy-apply-pi-performance` is reached through system/hardware setup only at `425`. That is what installs the memory-aware makepkg drop-in. Both `install-rpi4.sh:230` and `build-packages-rpi4.sh:136` use `mktemp -d` without establishing a disk-backed build directory. If `/tmp` is tmpfs on a target, source copies and compiler outputs compete with desktop RAM. The factory has separate disk-backed TMPDIR/cache binds (`image/build-rpi4-image.sh:283–294,381–386`), but the direct installer/current updater do not establish an equivalent default. The RC1 bootstrap does explicitly set two-job environment budgets.

The macOS wrapper bounds CPU affinity and exports `MAKEFLAGS`, but uses `RUST_BUILD_JOBS` rather than Cargo's `CARGO_BUILD_JOBS` (`image/build-rpi4-image-macos.sh:81–85`). CPU affinity is not a memory limit. I did not reproduce an OOM or a full factory peak-memory event.

**Proposed repair:** establish the Pi memory/job/compression budget and a checked, disk-backed build/cache workspace before the first makepkg call, including the first RC1 repair and direct install. Preserve an explicit user budget. Use Cargo's actual environment variable, add a documented container memory/CPU budget for local image builds, and bound xz workers/memory (`image/build-rpi4-image.sh:557` currently uses `-T0`).

**Regression gates:** on fixtures for 4GB, 8GB, and low `MemAvailable`, assert the budget of the very first required recipe and core build; prove outputs are on the chosen disk filesystem; fail before mutations when staging/cache space is insufficient. Measure actual 4GB and 8GB peak RSS, PSI, swap, I/O, and thermal/power status before claiming performance gains.

### F12 — P1 source-level security gap: factory-created pacman private identity is not scrubbed

**Verified source and inference:** the factory initializes `/etc/pacman.d/gnupg` while assembling the chroot (`image/build-rpi4-image.sh:362–363` and `install-rpi4.sh:127–128`). Final cleanup kills its agents (`497–499`) but does not remove/recreate that keyring or schedule generation of a unique local master key per device (`493–543`). Thus the constructed image retains the factory keyring state unless another, unobserved external step removes it; clones of that image would share it. This is a source-level finding, not an inspection of private-key bytes from a downloaded or mounted release image.

Upstream 4.5 explicitly accounts for this: [image-target helper](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/install/helpers/image-target.sh#L19) and [post-install initialization](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/install/post-install/pacman.sh#L27) defer local keyring initialization to first boot so machines do not share a master key.

**Proposed repair:** retain packaged public vendor keys while removing factory private identity, and initialize/populate an independent local pacman keyring on each first boot before package operations. Do not destroy the trust material on an already-owned system during ordinary updates. Add a mounted-root audit for secret key material and a first-boot dependency/receipt for successful initialization.

**Regression gates:** a factory image contains no usable local signing private key; two disposable first boots get distinct local fingerprints; package signatures remain enforced and offline owner setup still works. Never print private keys or include them in reports.

### F13 — P2 with a boot-recovery consequence: in-place updates lack the factory's hard initramfs verification

**Verified evidence:** the factory explicitly runs `mkinitcpio -P` and fails if it fails because package-manager hook failures do not reliably fail the transaction (`image/build-rpi4-image.sh:504–506`). The in-place updater has no corresponding Pi boot-verification step. `bin/omarchy-update-analyze-logs:7–12` merely prints a warning based on two English log phrases and returns success; the outer flow proceeds to restart handling. The factory's Hyprland parser check is likewise not run after an in-place compositor/core update.

**Proposed repair:** after kernel/firmware/core transactions, validate the Pi boot assets and initramfs with an explicit status/receipt, and fail before offering a normal reboot on a detected failure. Retain a known-good recovery path on spare media. Add an appropriate non-root compositor config check against the target Pi configuration. Do not treat text matching in the transcript as proof that the boot chain is sound.

**Regression gates:** simulate a successful pacman transaction whose initramfs hook failed, a full boot filesystem, a missing kernel/DTB/initramfs, and a config parse failure. Each must give a nonzero/explicit incomplete result and recovery guidance. A healthy update must still work over SSH/TTY without starting a compositor.

## 4.5 integration checkpoints, distinct from existing defects

The [4.5 release](https://github.com/omacom/omarchy/releases/tag/v4.5.0) and [announcement](https://omarchy.org/news/2026/11/omarchy-4-5/) establish the target release and new ARM work. They do not establish Pi 4 support. Review these incoming changes before resolving merge conflicts by choosing upstream wholesale:

1. **Repository/platform routing:** upstream [post-install pacman setup](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/install/post-install/pacman.sh#L8) now derives templates from `omarchy-hw-platform` and calls `omarchy-apply-pacman`. Its [template helper](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/install/helpers/pacman.sh#L8) has generic/Apple/NVIDIA/Qualcomm ARM choices, not `rpi4`. The existing `OMARCHY_PACMAN_PROFILE=rpi4` handoff is not consumed there. Preserve or explicitly register the Pi route, including channel changes/refresh/reinstall paths, so a normal operation cannot restore generic ARM or x86 repositories and invalidate the Pi guard. Any proposal to consume official Omarchy ARM packages needs its own ALARM dependency/ABI review.
2. **Update orchestration:** carry forward the Pi preflight and rebuild path when incorporating [the new upstream updater](https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/bin/omarchy-update). The upstream flow improves sudo lifetime/signal cleanup, restarts the shell before pending migrations, and changes later maintenance ordering. Import those deliberately; do not lose Pi guards, receipt retries, source tracking, or the dependency closure. Current Pi rebuilding also performs dependency installation before the keyring/full system upgrade, so preflight the complete package plan to avoid ad hoc partial upgrades or compilation against an incoherent rolling library set.
3. **Image identity/lifecycle:** 4.5 introduces trusted image-target and lifecycle-dispatch contracts. Its privileged platform detector deliberately ignores unprivileged fixture overrides. The current factory binds host `/proc` and `/sys` and injects a fake Pi model for Pi setup; that is not automatically sufficient input for the new root detector. Stage an explicit, supported image target before invoking incoming generic hardware/setup code. Test the exact factory path on an ARM Linux builder that is not a Pi.
4. **Provisioning:** merge the upstream lifecycle/re-key/recovery changes without dropping Pi Imager preseed, hostname readback ordering, source-checkout ownership transfer, grow-root/SDDM dependencies, or ARM64 offline Node staging. An upstream Apple or NVIDIA ARM path is not a replacement for Pi first boot. Ordinary package updates must not arm owner setup or replay factory account removal.
5. **Migrations:** audit added, changed, and renamed files against both sets of shipped per-user markers. Existing markers do not replay a changed same-named migration. Preserve explicit hardware guards on x86/Apple/NVIDIA kernel/boot repairs; do not blanket-skip all ARM migrations. New neutral UI/runtime migrations still need to run on Pi, while platform repairs must no-op there.
6. **Feature budget:** incoming video backgrounds, new applications, floating titlebars, language/input-method additions, and capture/remote-desktop support change package and resource requirements. Default-heavy features must be validated on 4GB first, with missing optional features reflected honestly in the UI. Any typography change should follow the user's Paper Mono preference through proper package/font licensing and glyph-fallback review; it is outside this install-only audit and was not implemented here.

## Test baseline and host limits

Host observations were read-only: Apple-silicon macOS/Darwin 27, 24 GiB RAM, about 49 GiB free on the host APFS data volume, `.git` about 1.2 GiB. No local `build/` or `build-output-rpi4/` directory was present. `/bin/bash` is 3.2.57; installed `/opt/homebrew/bin/bash` is 5.3.20. Python 3.15.0, Node 26.12.1, ShellCheck 0.11.0, xz, jq, and timeout are already installed. No Apple-platform build was needed, so no Xcode selection/build was performed.

Docker's current context is `orbstack`, but both `docker info` and `docker ps` fail because `/Users/preetham/.orbstack/run/docker.sock` is absent; `/var/run/docker.sock` is a dangling link to it. OrbStack is installed but no running OrbStack/Docker/QEMU/Lima process was found. I did not start a VM, daemon, or container. Its Linux free space is therefore unknown. `flock`, Linux `/proc`/`sysfs`, actual systemd/pacman/makepkg, mounted-image fsck, and native ARM ELF execution remain Linux-only coverage here. `dpkg-deb` is absent.

Tests ran serially with explicit installed Bash 5, temporary HOME, no global Git config, and outer guard executables that refuse accidental host `sudo`, `pacman`, and `makepkg`. Test-specific stubs still take precedence where the test intentionally exercises their argument flow. Repository files were not rewritten to make them pass on macOS.

| Result | Existing suites |
| --- | --- |
| Passed unchanged: 19 files | `raspberry-pi`, `rpi-imager-preseed`, `rpi-owner-hostname`, `rpi-display`, `rpi-performance`, `rpi-tune`, `rpi-update-safety`, `rpi-grow-root`, `rpi-hyprland-verify`, `rpi-upgrade-guide`, `update-sequence`, `update-keyring`, `first-run`, `provision-user`, `update-pacman`, `update-pacman-guard`, `update-status`, `migrate-scope`, `migrate-wrapper` |
| Host formatting failure, then passed with a temporary count adapter | `screensaver`: macOS `wc -l` emits a space-padded count; its exact `== 1` assertion fails. A fixture confirmed `<       1>`. Normalizing only standalone `wc -l` output through a temporary PATH wrapper made all six checks pass. No repository edit was made. |
| Partial run, host privilege step refused | `rpi-optimization`: compiler/compression budget assertions passed, then the outer guard refused its required `sudo` fixture application. Root-required setup/idempotence coverage remains outstanding. |
| Host dependency unavailable | `rpi-firmware`: exits 127 at missing `dpkg-deb`; no package/maintainer script was executed. |

`provision-user` returns success for its intended skill-symlink assertions, but emits a missing-`mise` warning on this host through a helper. That narrow fixture does not establish complete production finalization. The existing `rpi-hyprland-verify` test uses a mock chroot/Hyprland binary; it establishes helper behavior, not actual ARM parser compatibility. The tune suite uses simulated sensors/state, not hardware clock trials.

Additional checks:

- Bash 5 syntax checking passed for 40 installer, builder, image, update, and provisioning scripts.
- Warning-level ShellCheck on the two entry scripts, Pi updater, and image factory returned five warnings: three declaration/assignment status masking warnings (`SC2155`), one unquoted pattern comparison (`SC2053`), and the root-variable safety warning on removal of `$root_mount/boot` (`SC2115`). These are not a clean lint result; resolve or justify them when editing those paths.
- Isolated probes reproduced the RC1 already-advanced false success, required-package presence-only skipping, AUR failure masking, first-run finalizer failure masking, owner worker pending-state removal, manifest JSON corruption, caller-workspace deletion, missing-package migration stop, and split-release/catalog mismatch. They did not run real host account, hostname, network, package, mount, or service operations.
- Existing test logs are temporarily available at `/var/folders/bj/wt9g4l715m99l7rz2rjbtxkc0000gn/T/omarchy45-install-audit-2ti2fu13`. Gap probes use `omarchy45-gap-probes-hu_jbkaz`, migration probes `omarchy45-migration-probe-mcpxyp36`, factory probes `omarchy45-factory-probes-xmicnvqd`, and manifest probes `omarchy45-manifest-probe-0ngij15_` under that same parent temporary directory. These are disposable diagnostic evidence, not committed test additions or durable release artifacts.

### Storage and concurrency requirements

The source checks an image-size floor, not a host/VM free-space budget. Factory storage must accommodate the allocated part of the 12 GiB sparse image, downloaded rootfs, temporary boot copy, host-backed package archives and compiler work/cache, compressed output, and retained artifacts. Compression/catalog hashing reads the complete image; working storage is not just the compressed download size. `OMARCHY_IMAGE_SIZE_GIB` may need increasing for 4.5 based on measured transient usage, not finished-image estimates. Image and boot filesystem fullness must be checked separately.

For a future local build, use one bounded native ARM Linux build at a time, coordinate it with other active work, and measure free disk inside the VM as well as on macOS. A provisional 30–40 GiB of free Linux workspace plus host/container storage headroom is a planning allowance, not a measured guarantee. The current host's 49 GiB free does not prove its stopped VM has sufficient capacity. Keep package/build data on disk and set explicit memory/worker limits. Do not reserve all available RAM or logical cores merely because the 8GB target or build host is larger.

The installed updater requires at least 10 GiB free on `/` (`bin/omarchy-update-requires-free-space:10–14`) but does not check a separate build filesystem, TMPDIR, cache, or `/boot`. Keep the root safety check; add estimates/preflight for actual build/cache/boot locations rather than recommending `OMARCHY_UPDATE_FORCE=1` as a general solution. The documented supported storage floor is 32 GB, not the 12 GiB factory-image size.

## Proposed implementation sequence and release gates

These are proposed next steps for the parent task. Nothing in this section was executed or authorized as publication by this audit.

1. **Resolve the package contract before a full build.** Inventory every required command/unit/library and every pending migration package on Pi. Choose reviewed recipes and monotonic package versions. Make offline/static fixtures reject unresolved runtime dependencies, wrong architecture/repositories, stale required versions, incomplete artifact sets, integrity failures, dirty/unexpected source, and invalid manifests. Keep optional omissions visible and intentional.
2. **Fix failure and cleanup semantics.** Add focused regressions for F3–F9 and F12–F13. Establish disk-backed budgeted work before compilation. Preserve retry state after every failed phase. Validate current-source bootstrap behavior for the original installed updater and stopped/restarted updates. Add interruption cases without broad process kills or live-system mutations.
3. **Run Linux fixtures on an already provisioned bounded native ARM Linux environment.** Execute the focused Pi workflow gates, the root-required optimization fixture, firmware extraction fixture, update lock/free-space/pacman/conflict tests, migration queue tests, and provisioning tests. Require no unreported skips. Keep graphical acceptance in the disposable harness described by the task guide; the upstream ISO VM can cover shared desktop behavior but does not model BCM2711/V3D, Pi boot firmware, or physical HDMI/Wi-Fi/audio.
4. **Assemble one reviewable 4.5 candidate without publishing.** Require clean exact source and recipe commits, complete package inventory, strict JSON schema, valid compressed/extracted hashes, no factory accounts/SSH host identity/private pacman identity, correct public firmware licenses, no applied overclock, and the expected `main`/`origin/main` update checkout. Verify all required ELF architectures, dynamic dependencies, real ARM Hyprland parser output, enabled services and their executables, native Pi boot layout, and offline filesystem checks. Keep the audit and manifest beside the image.
5. **Validate first boot on disposable media for both 4GB and 8GB Pi 4 Model B.** Cover HDMI interactive owner setup; valid Imager username/hostname/key-only SSH/Wi-Fi; password-auth SSH when explicitly chosen; no network; partial/invalid preseed; interrupted growth/provisioning; already-expanded storage; hostname failure/readback mismatch; failed user finalization; and second boot. Assert account/source ownership, private credential permissions and cleanup, unique local package-signing identity, expected autologin removal, retry markers, and normal login without replayed setup.
6. **Validate in-place upgrades on cloned RC1 and alpha4 cards.** Preserve files, hostname, SSH keys/settings, Wi-Fi, display profile, user customizations, application data, firmware clock choices, and migration history. Test no recipe cache, no installed receipt, current source with failed prior package install, absent new runtime dependencies, source modifications/wrong remote/branch, package conflict, loss of network, low root/build/boot disk space, and interruption at each major phase. A successful retry must leave exact expected core/runtime versions and no pending migrations. Verify a second user gets their own migrations where the installation supports multiple users.
7. **Verify the running desktop and 4GB resource budget.** Check V3D/VC4 acceleration rather than software rendering; actual display input/output and saved modes across reboot; audible HDMI/analogue output; actual Bluetooth pairing and Wi-Fi/SSH operation; shell surfaces, notifications, locking, capture/annotation/recording, background behavior, and representative applications. Follow the visual-verification guide for screenshots/short recordings. Measure cold boot/login and update/build resource use at stock clocks under sustained load, including temperature, under-voltage/throttle flags, PSI, swap, peak RSS, and storage writes. Report 4GB and 8GB separately; no Pi 5 support claim.
8. **Validate distribution before any release action.** Ensure every catalog URL names an actual complete downloadable asset with matching byte count/hash, or provide the tested split/reassembly/local-catalog flow. Keep this candidate an artifact until the Pi 4 hardware/upgrade gates have explicit results. Release tagging currently triggers automatic publication in the workflow; do not use a release tag as a private validation mechanism.

An end-to-end release result should identify the tested source/recipe/image hashes, Pi 4 RAM model and storage, exact fixture/Linux/image/hardware coverage, unresolved skips, and recovery procedure. At this audit's completion only the source, metadata, and isolated fixture evidence above exists; the Linux assembly and physical Pi gates remain open.
