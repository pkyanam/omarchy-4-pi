# Omarchy 4.5 upstream and ARM64 compatibility audit

Audit date: November 6, 2026, America/New_York (network observations around November 7, 02:00–03:00 UTC). Target: Raspberry Pi 4 Model B, 4GB and 8GB. Pi 5 is future scope and has no hardware validation in this audit.

This is a source and package research report. No implementation file was changed; no merge, commit, push, installation, image build, or physical-device test was performed. The only output of this assignment is this report. Earlier hardware observations in this repository remain historical observations, not verification of 4.5.

## Decision and immediate blockers

Integrate the exact released tag through a reviewed merge, retaining the fork's Pi-specific installation, boot, update, provisioning, and resource policies. Do not replace the fork with an upstream tarball, follow moving `quattro`, or attempt to cherry-pick the entire release. The fork already contains Quickshell, Hyprland Lua configuration, the Quake console, security hardening, and substantial Pi safeguards.

Official Omarchy ARM64 binaries are now a realistic way to avoid compiling the desktop and applications on a 4GB Pi. Their existence does not make the upstream ARM ISO a Pi image, nor make an arbitrary mixture of Omarchy stable, Omarchy recipe master, and live Arch Linux ARM compatible. The initial integration must resolve these blockers first:

| Priority | Blocker | Affected files and concrete resolution |
| --- | --- | --- |
| P0 | Recipe pin is from September 4 and still describes the core pair as 4.0.2. | Review and replace `image/omarchy-pkgs.commit`, update the Pi recipe adaptations in `build-packages-rpi4.sh`, and test the resulting package contents and ownership. Changing `version` does not solve this. |
| P0 | The released stable desktop and current rolling ALARM desktop have different ABIs. | Select one coherent library/compositor/Qt set for `default/pacman/*rpi4*`, the installer, updater, and image factory. Stable has Hyprland 0.56.2 and titlebars 0.2.2; live ALARM has Hyprland 0.57.1 and newer Aquamarine/hyprgraphics SONAMEs. See the package matrix below. |
| P0 | The new settings recipe ships generic ARM boot and memory policy. | Extend Pi filtering to the new mkinitcpio baseline and runtime-profile behavior. Keep the Pi firmware/U-Boot/ext4 route. Prevent the vendor zram `90-omarchy.conf` from overriding the Pi `50-omarchy-pi.conf`; merely moving the Pi size setting later would still inherit the vendor's zstd compressor setting. |
| P0 | Qt 6.12 requires the matching patched Quickshell path. | Pair the shell's `OmarchyLoadPatch` pragma with the upstream patched Quickshell package, or implement and verify a complete equivalent compatibility change. A bare ALARM `quickshell` package name is insufficient evidence. |
| P0 | Old mise can eagerly install the new lazy defaults. | Require mise ≥2026.10.11 before installing 4.5 declarations or running their migrations. The current Pi pin supplies mise 2026.9.1; the installer only checks whether it is installed. Add version reconciliation, not just presence checks. |
| P0 | Upstream package configuration does not understand the fork's `rpi4` channel. | Adapt `install/helpers/pacman.sh`, `omarchy-apply-pacman`, refresh/post-install paths, and package guards together. Keep the source tied to `pkyanam/omarchy-4-pi`, and prevent official core packages from replacing the locally adapted core pair. |
| P0 | Existing-install updates do not reconcile the full new runtime. | `omarchy-update-rpi4` currently runs only `install_arm_packages` before rebuilding the core; it does not run `install_official_packages`, compose the new ARM package lists, update existing recipe packages by version, or satisfy new application migrations. Resolve dependencies before migrations and keep failure retryable. |
| P0 | The old updater/hook process remains running during the transition. | Supply an explicit bootstrap or staged handoff to current update/reload guards. Test replacement of the running compositor and old notification server. Include upstream's final release fixes `3e634acf` and `81d0bc90`. |
| P1 | New migrations install packages the current Pi resolver cannot see. | Provide audited binaries/recipes for titlebars, Monologue, Hype, Disktree, Gliff, Signed, and the patched power daemon, or make deliberate Pi-specific exceptions. Preserve migration order and non-zero failure behavior. |
| P1 | New floating mode can restore graphics effects the Pi currently disables. | `workspace-modes.lua` enables shadows when entering floating mode. Apply an explicit Pi policy after considering this behavior; preserve floating/dock functionality and measure before claiming an efficiency gain. |
| P1 | The package builder unconditionally skips source integrity verification. | Limit any local-source exception to the custom core payload. Font and other downloaded sources should retain checksums/signature validation; repository packages must retain required signature verification. |

These are integration requirements, not findings that a deployed 4.5 Pi system has already failed. This audit has no access to such a system.

## Source identities and exact divergence

| Source | Identity and interpretation |
| --- | --- |
| Fork baseline | `393f48c3cd6e32e36111064fa99d2f59e4449aa5`, `pkyanam/omarchy-4-pi`; tracked tree clean at assignment start. The parent's untracked `plans/omarchy-4.5-pi4.md` was already present and is not part of the comparison. |
| Release tag | Local `upstream-v4.5.0`, fetched by the parent from upstream `refs/tags/v4.5.0`; peeled commit `ac2690cd7be4f47e4a255f5e2e78d904d436b068`. The release API reports publication at `2026-11-05T05:36:53Z`. [Release][release] and [commit][tag-commit]. |
| Shared ancestor | `d3cfd53b997f8bdcf776b8db68bf0d735e7a065d`, September 22, 2026, “Merge pull request #10217 … ocaml-removal-no-update.” |
| Existing recipe pin | `99234a4fbb61b46225b2e9e560e114fbfebe8a95`, September 4, 2026. [Recipe repository commit][old-recipes]. |
| Package source near publication | `13260536c28cfb92fa3e767693c55b434aa27773`, the latest master commit returned before release publication. It is useful evidence, not a released package lock. |
| Audited final-release recipe candidate | Recipe `rc` resolved to `c7a1ef7f86cccab072fb11f22564862c03f50199`. Its core pair pins `ac2690cd…`, `pkgver=4.5.0`, `pkgrel=3`. Pin this SHA if adopting these recipes; do not store the moving word `rc`. [Core recipe][new-core] and [settings recipe][new-settings]. |
| Moving master warning | Recipe master resolved to `f6629ab484fc9dc0336e5d2cbb29124f8b4af951`, but its core recipe still pointed at `a948d8a6…`, 4.5.0-2. The API comparison of that source against the final release is diverged, 10 commits ahead/1 behind. Do not equate a `_tag='v4.5.0'` label with the actual pinned commit. [Comparison][recipe-source-compare]. |

Exact Git results against the fixed fork baseline:

- `git rev-list --left-right --count 393f48c3...upstream-v4.5.0`: **100 fork-only / 917 upstream-only commits**. Commit counts include merges.
- From the shared ancestor: **111 fork-modified or added paths**, **4,246 upstream changed paths**, and **20 paths modified on both sides**, with rename detection disabled for reproducible path counts.
- Direct final-tree comparison: **4,337 changed paths** without rename detection. The regular rename-aware shortstat reports 4,318 files, 478,619 insertions and 32,277 deletions; these are different counting methods, not contradictory measurements.
- Upstream changes include 325 `bin/` paths, 69 `install/` paths, 222 `shell/` paths, 105 migration paths, 486 test paths, and 2,538 manual paths. Translated documentation accounts for much of the apparent scale; this is still a broad runtime change.
- `version` contains `4.0.0.alpha` in **both** the fork and released tag. Packaged runtime version reporting queries pacman. The fork README's 4.0.4 description is not a reliable package-recipe identity: the actual pinned recipe says 4.0.2, and `OMARCHY_SRC` overrides its source with this newer fork.

The comparison was performed from the now-available tag. No duplicate upstream fetch or full `omarchy-pkgs` clone was made. Package source inspection used narrow raw files and GitHub APIs.

## Upstream work already present

These commits are ancestors of `393f48c3`; they must not be presented as missing fixes or reimplemented independently:

| Commit | Existing protection or feature | Consequence for integration |
| --- | --- | --- |
| `d3cfd53b`, `73a09695` | OCaml removal authorization isolation and its security coverage. | Keep later upstream evolution, but do not duplicate the original repair. |
| `0a65b45a` | Reject path-like hook/state names. | Retain the validation contract in `omarchy-hook` and `omarchy-state`. |
| `b44fb747` | Screen-recording state moved out of world-writable `/tmp`. | The recording merge should preserve the newer private-state behavior and the Pi `wf-recorder` backend. |
| `a73bcbfc` | Removed unsafe project-bin PATH injection. | Do not restore the deleted PATH behavior while resolving offline mise setup. |
| `70047956` | Hardened lock authentication command lookup. | Preserve the shell's authentication boundary while updating IPC and plugins. |
| `96ed473c` | Repairs privileged artifacts from retired installers. | Keep the migration for late updaters even though upstream retired its frozen one-shot test. |
| `df819a6f` | Hardens input-group, asdcontrol, and SSH setup paths. | Still take the additional SSH no-authorized-key fix below. |
| `6ea32155` | Windows VM password removed from RDP argv. | Already inherited, even though that workflow is not a Pi release priority. |
| `129c67e2` | Standard terminal clipboard/select-all shortcuts. | Some 4.5 hotkey behavior is already in this fork. Compare actual bindings rather than resetting them from a release-notes checklist. |
| `73b4fc0d`, `aa5c4beb`, `3208fe09` | Elsewhen package-link migration repairs. | Preserve users' city/settings data while taking the later in-tree `omarchy.elsewhen` migration. |

The fork also already has a single-process Quickshell desktop, plugin manifests/capability facades, Lua `hl.*` configuration, and the Quake console. Omarchy 4.5 expands these systems; it does not introduce them from scratch here.

Existing Pi work includes signed ALARM sources, checked recipe provenance, factory filesystem and connectivity gates, owner/preseed provisioning, firmware payload checks, root-growth retry, native health reporting, bounded builds, private capture state, update refusal/retry, CPU policy, half-RAM zram, app-scope oomd, logging/writeback limits, and opt-in clock trials. The protected path inventory at the end is the starting preservation list.

## Released functionality and its integration boundary

The announcement identifies floating workspaces/dock, language/input support, captive portals, new applications, dictation, notification changes, and ARM installers. The actual release tree is the implementation authority. Apple Silicon installation and the ARM ISO's NVIDIA platforms do not advertise Raspberry Pi support. [Official announcement][announcement].

| Runtime area | Concrete source delta from this fork | Pi 4 integration action |
| --- | --- | --- |
| Workspace model | New `default/hypr/monitor-workspaces.lua` and `workspace-modes.lua`; compositor-side slot mapping, monitor ownership, tagged floating/minimized windows; dock under `shell/plugins/dock/`. | Integrate as one feature set with matching bindings, CLI helpers, titlebars and tests. Preserve monitor-specific user settings and special workspaces. |
| Shell dispatch | `6762769b` introduces direct Hyprland global shortcut delivery; `c231097d` changes `omarchy-shell` to the shell's own IPC socket through `shell/Commons/ShellIpc.qml` and `IpcRegistry.qml`. | Update the CLI, server and every target together. A source-only CLI replacement talking to an old shell is not a valid upgrade test. |
| Notifications | New service/model/toast implementation, sender grouping and keyboard actions; cleanup migration `1792648436.sh`. | Verify DND preservation, action buttons, notification ownership, lock interaction and readiness after update. Do not infer success from a bar ping. |
| Bar configuration | `centerBegin/center/centerEnd` sections, tray drawer, placement/orientation changes, opaque/glassy background field, in-tree Elsewhen ID. | Migrate existing `shell.json`; do not overwrite a curated layout with fresh defaults. Include `1791968925.sh` and `1791969355.sh`. |
| Languages/input | `default/i18n/`, `omarchy-i18n`, language/locale helpers, Fcitx engine packages, XKB files and themed candidates. | Package locale/XKB assets and helpers with the matching menu and QML. This dependency affects ordinary error messages and menu actions even for English users. |
| Agents/tooling | More usage providers, accounts and lazy default tools; `etc/mise/conf.d/omarchy-tools.toml`, `omarchy-mise-default-tools`, offline shim generation. | Upgrade mise first; preserve account secrets, user overrides and the Pi's bounded workload scope. No agent CLI's ARM support is proven merely by its launcher existing. |
| Network | Connectivity check configuration and captive-portal helper/service/UI. | Retain NetworkManager, Pi firmware and Imager Wi-Fi handoff. Test first boot without Internet as well as captive portal transitions. |
| Capture/media | Recording PID/status/locking and backend fallback improved; new OWE handling and screenshot/recording actions. | Prefer the new upstream implementation with Pi fallback preserved. Test desktop+microphone mixing and CPU-encoding load. |
| Setup/lifecycle | New platform detector, image-target helper, deferred hardware setup and lifecycle dispatcher; owner progress renderer and language setup changes. | Adapt at the Pi boundary rather than importing the UEFI image workflow wholesale. The Pi factory does not currently create upstream's image-target manifest. |

The release contains 19 theme intro videos totaling **86,196,373 uncompressed bytes**; this fork contains none. Total tracked theme payload grows from 66,400,198 to 167,578,770 bytes. The new recipe splits intros into `omarchy-themes-intros`, but also makes that package a hard core dependency. Disabling playback and excluding the download are separate decisions. Recommend static backgrounds and disabled intro playback by default on Pi 4, with the feature available as an explicit optional install; implement that as a declared Pi package variation rather than a missing dependency.

### Hyprland Lua requirements

The fork is already Lua-based, so converting a legacy `hyprland.conf` is not the task. New calls relative to the fork include:

- `hl.dsp.global` for the direct shell shortcuts.
- `hl.dsp.workspace.change_id`, `hl.get_monitors`, `hl.get_monitor`, `hl.get_workspaces`, `hl.get_active_workspace`, and `hl.get_window` for per-monitor workspace reconciliation.
- `hl.dsp.window.tag`, `hl.dsp.window.center`, and `hl.dsp.window.alter_zorder` for floating/dock/window handling.
- `hl.plugin.load`, `hl.plugin.hyprbars.add_button`, and guarded `hl.get_loaded_plugins` for titlebars.

Use the released, patched **Hyprland 0.56.2-7** as the first compatibility target if selecting the release's stable package set. This is an observed release package target, not a proof that every earlier 0.56 build is compatible. The installed titlebar plugin must match the compositor build it was compiled against; matching only the version string is weaker than matching the build/recipe provenance. The source checks for the plugin file before loading it, so a missing package may quietly produce floating windows without titlebars. A parser-only image gate will not catch that omission. [Stable compositor recipe][stable-hypr-recipe] and [stable titlebar recipe][stable-titlebars-recipe].

Preserve `require("default.hypr.raspberry-pi")` in `default/hypr/envs.lua` and its `AQ_NO_MODIFIERS=1` compatibility setting. It is a fork addition absent upstream, not dead code. Current `hl.env` is the compositor's environment API; use an isolated, hardware-tested A/B change before removing this workaround. [Hyprland environment API][hypr-env].

The new floating setup deliberately enables shadow rendering if it is currently disabled. Therefore retaining the old `looknfeel.lua` settings alone does not preserve the Pi's graphics budget. Audit mode transitions and toggle order, including the new no-animations mode, instead of assuming a global “no shadow” setting remains effective.

### Quickshell and Qt requirements

The release starts `shell/shell.qml` with `//@ pragma OmarchyLoadPatch`. The associated Omarchy Quickshell patch recognizes that pragma and constrains unversioned QtQuick imports to 6.11, avoiding the Qt 6.12 `Color` singleton collision, including dynamically loaded plugins. Many first-party references were also qualified as `Commons.Color`; that does not eliminate the third-party-loader requirement. The unpatched ALARM `quickshell 0.3.2-1` is consequently not an interchangeable substitute just because the package starts. [Pinned Quickshell recipe][stable-quickshell-recipe] and [loader patch][quickshell-patch].

The selected stable package is `quickshell 0.3.2.r7.g2b4501a-1`, source commit `2b4501a282689792b62e94f3fb30d8f512324fe6` plus the loader patch. The previous recipe pin's `quickshell-git` is `0.3.0.r20.g28771c7-3`, with a different source and no such patch. The Pi installer does not currently install that recipe; it installs whatever `quickshell` the ALARM resolver exposes, so inspecting the old recipe is not evidence of the installed binary's version.

New shell usage includes Hyprland toplevel/monitor refresh APIs, desktop-entry lookup/heuristics and global shortcuts. Keep Wayland layer surfaces, IPC, notifications, PAM, polkit, PipeWire and SVG support enabled. The aggregate shell must remain one long-running process. Quickshell itself documents rebuild sensitivity across Qt updates; a fixture or `--version` probe cannot replace launching the actual shell and its lazy panels with the selected Qt packages. [Quickshell installation guidance][quickshell-guide].

## ARM support: useful packaging, different platform contract

Upstream's `omarchy-hw-platform` recognizes `x86`, generic `aarch64`, Apple, Qualcomm, N1x and GB10 families. It uses trusted image manifests or live hardware identity. A Pi's Broadcom device tree falls through to generic `aarch64`; there is no `aarch64-raspberry-pi` case. The package templates for that generic platform use ALARM plus Omarchy's ARM64 repository. [Detector][platform-detector] and [repository helpers][pacman-helper].

This brings reusable native ARM packages and sensible architecture checks. It does **not** supply the Pi's firmware partition, `start4.elf`/firmware configuration, U-Boot/extlinux route, Pi DTBs/overlays, root-growth service, Imager preseed, Broadcom Wi-Fi/Bluetooth payload or V3D scanout policy. Those remain owned by this fork. ALARM's board-specific instructions also distinguish its Pi setup from a generic ARM system. [ALARM Pi 4 platform][alarm-pi4].

Important differences visible in the release:

- The new settings runtime profile includes boot files for both architectures. Generic ARM's mkinitcpio baseline includes `plymouth`, `encrypt` and `btrfs-overlayfs`, serving upstream's UEFI/encrypted-root layouts. It does not describe this Pi ext4 image. [Runtime-profile marker][runtime-profile] and [baseline][mkinit-baseline].
- `omarchy-lifecycle-dispatch` registers platform boot verification for Apple Silicon, while plain `aarch64` operations return a no-op. `omarchy-update-boot` therefore does not establish that a Pi's firmware, U-Boot, kernel, initramfs and root reference are consistent. Add a Pi-specific verification path or equivalent explicit updater gate. [Dispatcher][lifecycle-dispatch] and [update verifier][update-boot].
- `install/omarchy-aarch64.packages` adds `zram-generator` and `rtkit`. The fork reads only the base list and manually adds zram; it needs to account for the new additions, including checking realtime audio scheduling.
- The recipe has conditional support for a future platform pacman guard, but the corresponding `default/libalpm/scripts/omarchy-platform-guard` is absent from the released source tree. That conditional cannot be cited as Pi protection in this release.
- New hardware leaves have their own device predicates. Preserve the fork's tolerance of absent `/sys/class/dmi` data and keep `install/hardware/raspberry-pi.sh` in the orchestration. Generic ARM detection must not cause Apple/Qualcomm/NVIDIA boot or firmware work on a Pi.

ARM64 also does not prove a vendor binary runs on Cortex-A72. Compiled local packages should retain ALARM's generic architecture baseline, and vendor binaries need an actual Pi smoke test for unsupported instructions and shared-library requirements. Do not adopt Apple, Snapdragon, N1x kernels, firmware or CPU tuning on this board.

## Package availability and ABI evidence

The following were read directly as archive databases, not inferred from `arch=('aarch64')` in recipes:

- [Omarchy stable ARM64 database][stable-db]: 219 entries; HTTP Last-Modified `2026-11-07 00:47:51 GMT`.
- Omarchy rc ARM64: 219 entries, same key release versions in this observation; edge: 284 entries with newer desktop packages.
- [Official ALARM extra database][alarm-extra]: 13,166 entries; Last-Modified `2026-11-07 01:00:14 GMT`. Core and alarm were also checked.
- [Omarchy's stable ALARM extra mirror][stable-arm-extra]: Last-Modified `2026-10-20 18:33:25 GMT`, with older compositor libraries. Its core/alarm mirror metadata is dated October 20 as well. The package repository README's statement about live ARM repositories must not substitute for measuring the actual channel mirror. [Builder mirror selection][pkgs-builder].

These are mutable audit observations. They are not a lockfile, and the audit did not run pacman's Linux dependency solver.

| Component | Omarchy stable ARM64 / its stable ALARM mirror | Official live ALARM | Compatibility significance |
| --- | --- | --- | --- |
| Core pair | `omarchy` + `omarchy-settings` 4.5.0-3 | Absent as stock ALARM packages | Rebuild the fork pair; do not install the official pair over the Pi port. |
| Hyprland | 0.56.2-7 | 0.57.1-1 | Choose the compositor with its dependencies and plugin. |
| Aquamarine | Omarchy 0.15.1-1.3, SONAME 14 | 0.16.0-1, SONAME 15 | A hard, observable library boundary. |
| hyprgraphics | Mirror 0.5.1-4, SONAME 4 | 0.6.0-1, SONAME 5 | Stable Hyprland explicitly depends on SONAME 4. |
| hyprutils | Mirror 0.14.2-1 | 0.14.3-1 | Both advertise SONAME 13; do not incorrectly call this the main incompatible SONAME. |
| hyprwire | 0.3.1-3 | 0.3.1-3 | Both advertise SONAME 3 in this observation. |
| hyprlang | 0.6.8-5 | 0.6.8-5 | Both advertise SONAME 2. |
| Titlebars | 0.2.2-2, depends on `hyprland=0.56.2` | Not available as a stock ALARM package | New recipe master/edge has 0.3.0-4 for Hyprland 0.57.1-2. |
| Quickshell | 0.3.2.r7.g2b4501a-1, patched | 0.3.2-1 | Loader patch and Qt compatibility must be preserved. |
| Qt base | 6.12.0-3 | 6.12.0-3 | Same base version observed. |
| Qt declarative | Mirror 6.12.0-1 | 6.12.0-4 | Stable Quickshell was built against `-1`; inspect private-ABI/build changes before mixing. |
| Qt Wayland | 6.12.0-1 | 6.12.0-1 | Keep it aligned with the other Qt packages. |
| Mesa / Broadcom Vulkan | Re-query when locking the stable image | 1:26.2.6-1 | A working compositor is not proof of browser video decoding. |
| `linux-aarch64` | Mirror 7.2.11-1 | 7.3.1-2 | Both need board/boot verification; switching mirrors also changes the kernel candidate. |
| Pi U-Boot | 2025.01-2 | 2025.01-2 | Exact version and SHA matched across the inspected alarm databases. |
| Pi firmware | 20260311-1 | 20260311-1 | Exact version and SHA matched across the inspected alarm databases. |
| systemd / glibc | 262.1-1 / 2.43+r22+g8362e8ce10b2-2 | Same versions observed | Record these in any image manifest; do not treat the mirror as an entirely different distribution. |
| Portal / session manager | Check selected stable closure | `xdg-desktop-portal-hyprland` 1.5.0-1; `uwsm` 0.27.1-1 | Resolve against the chosen compositor and launch the actual session. |

For additional binary evidence, the stable Quickshell archive (2,090,879 bytes) was downloaded into memory, its `.BUILDINFO` inspected with the existing system tar, and its SHA-256 checked against the database:

```text
quickshell-0.3.2.r7.g2b4501a-1-aarch64.pkg.tar.zst
SHA256 e1227d2930f84b78284cdffab8331e6a47632b2f65ee64945d785da1eb659fef
BUILDINFO: qt6-base 6.12.0-3, qt6-declarative 6.12.0-1,
           qt6-shadertools 6.12.0-1, qt6-svg 6.12.0-1,
           qt6-wayland 6.12.0-1
```

Detached `.sig` URLs for stable Hyprland, Quickshell and titlebars each returned HTTP 200 (119 bytes). This proves advertised signature artifact availability, **not** that this audit cryptographically validated those signatures. Installation/build gates must verify them using the trusted Omarchy/ALARM keyrings. No binaries were installed or run on the Mac.

### Application binaries are much less scarce than the old exclusion list suggests

These native/any package entries were present in the official Omarchy stable ARM64 database:

| Packages | Observed versions | Pi decision |
| --- | --- | --- |
| Hype / Signed / Disktree | 0.6.0-1 / 0.3.1-1 / 0.11.0-3 | Suitable binary candidates for the 4.5 migrations; runtime and UI still need testing. |
| Monologue / Gliff | 0.3.1-1 / 0.4.2-1 | Do not compile by default on Pi. Verify camera/capture and remote-session indicator behavior. Installing Gliff does not authorize enabling SSH. |
| Omasnap / OWE / ttfx | 1.25.0-1 / 0.2.13-1 / 0.5.0-3 | Core feature candidates. `owe-lockfeed` also exists, but the base list stopped explicitly requiring it; resolve actual file ownership/dependencies. |
| Omacalc / Omacut / Omawrite | 0.3.1-1 / 0.7.2-1 / 0.7.2-1 | Retain desktop functionality without expensive factory source builds where binaries verify. |
| Superwhisper | 1.2.0-1 | Has a native ARM64 vendor archive, checksums and minisign verification in its recipe. Local inference performance/Vulkan support on Pi 4 is unverified; no inference benchmark or cloud enrollment was performed. [Recipe][superwhisper-recipe]. |
| mise / yay / ufw-docker | 2026.11.2-1 / 13.0.1-1 / 251123-2 | Useful binary replacements for old local builds, subject to the selected package trust/update policy. |
| Icon/font and editor integration | `yaru-icon-theme` 26.10.3-3, JetBrains basic Nerd font 3.5.1-2, `omarchy-nvim` 2026.9.21-5 | Preserve glyph coverage and custom user font choices; do not conflate the icon font with UI typography. |
| Previously excluded GUI packages | `hyprland-preview-share-picker` 0.2.1-3, Obsidian 1.15.0-1, Pinta 3.1.2-1, tzupdate 3.1.0-2 | The claim “no ARM-compatible build” is now stale for these official repository entries. Reclassify after dependency and Pi usability checks. |
| Patched power daemon | `omarchy-power-profiles-daemon` 0.30-3 | Provides/conflicts with stock power-profiles-daemon. Its CPPC laptop motivation does not prove Pi governor benefits. |

Literal package-name absence does not prove unavailability: ALARM `neovim` provides `nvim`, for example. Build a resolver that understands provides/replacements and distinguishes required desktop packages from optional applications. Do not silently skip a required package and still call the result complete. `dotnet-runtime` remains unresolved by literal-name lookup in the sampled repositories; do not claim the dependency closure of Pinta is validated from its entry alone.

Keep the existing exclusion for an unverified Pi GPU recorder path: `wf-recorder` remains the tested design choice in this port. The fact that a recorder recognizes Broadcom in its source is not proof that this ALARM Pi 4 kernel/driver combination offers a usable hardware encoder. Likewise, emulation packages may have ARM builds but remain a deliberate resource/scope exclusion.

### Recommended package strategy

For the first fresh 4.5 test image, prefer the **released stable compositor/Qt closure**, with locally built Pi core/settings packages. This is closer to the actual 4.5 release than updating to the unrelated 0.57 recipe train during the same port. Verify all Pi boot packages exist in that closure and retain the board's boot layout. The mirror is mutable, so cache exact package archives, SHA-256 values, signatures, database hashes and build-source identities for reproducibility.

For an existing rolling Pi that already installed newer ALARM libraries, do not downgrade selected libraries in isolation. Either validate a whole coherent stable-channel transition against a disposable copy of that installation, or support a separate rolling-desktop closure with a patched Hyprland 0.57.1 and matching 0.3.0 titlebar build, plus matching Quickshell/Qt. The latter is plausible from observed edge binaries, but is a second validation target, not an automatic property of the released source. Do not make an unreviewed `-Syyuu` mirror change on a user's card.

The current guard rejects **any** `omarchy.org` package server and any repository beyond `core/extra/alarm/aur`. If adopting official packages, update the policy deliberately: architecture and approved channel/host, signature requirements, local-core replacement protection, and source-remote restrictions must all remain explicit. Prefer a small Pi-owned package selection/repository or a carefully protected Omarchy repository over unrestricted channel adoption. Do not resolve the problem by deleting the guard.

## Recipe audit and required changes

### What the present pin and builder actually do

At `99234a4f…`, both core recipes advertise 4.0.2 and pin source `346e69e1…`; the fork passes `OMARCHY_SRC`, so the actual payload is its staged checkout. Four packages are built locally: `omarchy-keyring`, `ttf-jetbrains-mono-nerd-basic`, `omarchy-settings`, and `omarchy`. Core/settings are architecture-specific because their dependencies and system files vary, even when much of their payload is scripts/QML. [Old core recipe][old-core] and [old settings recipe][old-settings].

`ensure_package_sources` checks a cached checkout's origin and cleanliness and checks out the reviewed SHA. An explicit `OMARCHY_PKGS_PATH` bypasses that path. The builder itself searches explicit/sibling/cache checkouts and records their HEAD, but does not independently enforce the review pin or dirty-tree identity. Preserve the explicit developer override, while making production manifests distinguish it from a clean pinned build.

The local source filter removes the old Limine directory/autostart and only the original `omarchy_hooks.conf` and `thunderbolt_module.conf`. The settings-recipe filter also removes references to those old backup entries. It does not understand the release's `00-omarchy-hooks.conf`, `omarchy_vconsole.conf`, `i2c_hid_of_module.conf`, or runtime-profile semantics. The recipe is executable build logic, not merely a list of copied files, so its assertions and file-removal rules must be adapted as well as its inputs.

### What must change before using a 4.5 recipe

1. Use the final-release core pair from an immutable reviewed recipe SHA such as `c7a1ef7f…`; verify its `_commit` equals `ac2690cd…`, while deliberately overriding its payload with the integrated fork. Give the fork packages a documented version/release identity that cannot be silently superseded by the official core pair.
2. Preserve the security package ownership transition. New recipes move passwordless-sudo helpers and a revocation hook into settings; runtime adds the `omarchy-security-functions` dependency. Install core/settings in one transaction and verify package removal/upgrade hooks still have their targets. Do not keep the old scriptlet merely because the old recipe builds. [Settings scriptlet][new-scriptlet] and [sudo lifecycle source][sudo-source].
3. Decide how to satisfy new hard dependencies `omarchy-speedtest` and `omarchy-themes-intros`. The latter can be a deliberate Pi optional-feature variation; it must not be an unexplained `--nodeps` hole. Preserve core speed-test functionality or explicitly adapt its command/UI.
4. Explicitly exclude or replace the generic initramfs/boot payload for Pi. Recheck pacman `backup=()` entries against actual packaged files and adapt the recipe's mkinitcpio assertions; blindly deleting every boot file can itself make the new recipe's invariant checks fail.
5. Keep the release's new service/config packaging where applicable: realtime audio dependency, connectivity configuration, global mise declarations, camera access unit if relevant, sudo timeout/lifecycle, and the normal user notification service. Review the exact release source rather than assuming every conditional stanza in current package recipes ships here.
6. Handle the new vendor zram file. A practical Pi adaptation is to omit it from the Pi settings package, or mask that exact vendor basename with an `/etc` symlink to `/dev/null`, retaining the existing Pi default and administrator overrides. If choosing a new explicit compressor policy, verify support in the selected kernel instead of carrying the historical LZO-only observation forward as a fact about all new kernels. [Generator precedence][zram-doc].
7. Avoid introducing upstream whole-RAM/zstd reclaim assumptions, zswap policy or generic USB power changes without evaluating interaction with `default/pi/*`. The Pi writeback, oomd, logging, CPU and no-overclock defaults must remain the effective installed policy, not just files in the repository.
8. Upgrade existing mise installations. The old required-recipe loop skips an installed `mise-bin`; changing the pin will not upgrade it. The release's project guide explicitly requires **mise 2026.10.11+** for lazy defaults. Use its offline `reshim --system` setup with a verified binary and preserve pinned user tools. [Release mise guide][mise-guide].
9. Keep the ARM64 Node bundle in factory provisioning until an offline-first-use contract is explicitly replaced and tested. Upstream `mise-work.sh` now only creates work directories, and user setup generates offline lazy shims. Removing the old unpack code without arranging the staged Node bundle for the new mechanism would remove the fork's offline guarantee. Do not restore `mise use -g node@latest` over a user's configuration as a shortcut.
10. Restrict `--skipinteg`: local source override does not justify skipping downloaded font or third-party source integrity. `--nodeps` during construction of a mutually dependent local pair is not a substitute for a final dependency-checked installation and package metadata audit.

The recipe changes affect reported versions, package ownership/scriptlets, runtime patches and boot/memory filtering. Raising the pin alone can introduce new failures even when a core package builds successfully.

## Merge forecast and Pi preservation rules

The read-only legacy three-tree comparison (`git merge-tree <shared-base> 393f48c3 upstream-v4.5.0`, not `--write-tree`) found conflict markers in **13 files**. It did not change the index or working tree. This is a forecast; Git's eventual rename/merge machinery may produce different hunk presentation.

| Forecast text conflict | Resolution requirement |
| --- | --- |
| `bin/omarchy` | Keep the `pi` command group and route metadata while incorporating upstream groups/routing. |
| `bin/omarchy-capture-screenrecording` | Prefer new PID/lock/status/cancel handling and improved fallback; retain Pi `wf-recorder`/mixed-audio behavior and private state. |
| `bin/omarchy-provision-owner` | Retain Imager hashed-password, keymap, hostname, timezone, authorized-key and SSH policy handoff; take the new language/progress/lifecycle logic and shared-ESP safeguards. |
| `bin/omarchy-refresh-pacman` | Support the actual Pi package policy before any config write; preserve the preflight guard and safe backup/render behavior. |
| `bin/omarchy-update` | Keep Pi preflight before mutations; adopt final sudo keepalive/cleanup, shell-before-migrations, failure propagation and restart phases. |
| `bin/omarchy-update-aur-pkgs` | Preserve local core exclusion and Pi package guard; take `GOROOT/GOBIN` cleanup and upstream failure behavior. |
| `bin/omarchy-update-confirm` | Keep fork-specific update destination and ext4 expectations; incorporate changed release UX/messages. |
| `bin/omarchy-version-channel` | Report the Pi source/package policy honestly; avoid reporting generic stable merely because one mirror matches. |
| `default/omarchy/omarchy-menu.jsonc` | Take the new recorder `--status` predicate, which handles both backends. Retain relevant Pi affordances and hide unsupported boot/kernel/reset operations. |
| `install/hardware/apple/fix-spi-keyboard.sh` | Retain no-DMI tolerance; upstream independently fixes it too, so the apparent conflict is not a reason to discard either hardware path. |
| `install/post-install/pacman.sh` | Preserve the Pi profile and avoid replacing it with generic ARM stable templates. Keyring initialization must remain per-device. |
| `install/user/mise-work.sh` | Resolve old offline ARM Node staging versus new lazy system declarations as a behavioral migration. Do not combine both user-config-writing policies accidentally. |
| `test/shell.d/provision-user-test.sh` | Preserve the self-contained Pi fixture while taking changed user provisioning behavior. |

Seven other jointly changed files are textually mergeable but still require semantic review: `bin/omarchy-channel-set`, `bin/omarchy-screensaver`, `bin/omarchy-update-dev`, `bin/omarchy-update-keyring`, `bin/omarchy-upgrade-to-quattro`, `default/hypr/envs.lua`, and `install/hardware/all.sh`. For example, a clean merge can preserve the Pi branch while new downstream helpers still reject the `rpi4` channel. Textual cleanliness is not compatibility evidence.

Additional upstream additions can conflict with Pi assumptions without sharing a modified file: package templates/helpers, settings runtime profile, mkinitcpio fragments, zram vendor file, new migration dependencies, lifecycle boot no-op, floating effects, mise defaults, and the image-target system. Review these explicitly rather than considering only Git conflicts.

Preferred strategy:

1. Prepare a separate reviewable integration branch after this initial audit; keep the original baseline reachable. Do not develop on the deployed updater's canonical checkout.
2. Merge the exact release commit once, retaining history so future upstream ancestry remains meaningful. Resolve conflicts by behavior; avoid wholesale `ours`/`theirs` for shared files.
3. Land coherent follow-up units for Pi package policy, recipe adaptation, updater/transition, migration adaptation and UI/resource defaults. Maintain the existing single-purpose tests for each boundary.
4. Use isolated cherry-picks only if a narrowly necessary bootstrap/security fix must reach existing Pi users ahead of the full port. Document dependencies and take final release versions of evolved fixes; do not replay intermediate passwordless-sudo/USB authorization designs that the release subsequently changed or removed.

## Additional upstream fixes to prioritize

These commits are in the release but not ancestors of the fork baseline. Links use immutable upstream commit identities.

| Priority | Commit / files | Why it matters here |
| --- | --- | --- |
| P0 | [`3e634acf`][fix-migration-shell], `bin/omarchy-update` | Restarts a stale shell before migrations that call current IPC. Necessary for an actual running-desktop upgrade. |
| P0 | [`81d0bc90`][fix-reload], `omarchy-hyprland-reload-guard` | Leaves a replaced running compositor from reloading config for its successor. Package hooks must travel with their executable. The very first upgrade from an old image also needs bootstrap consideration. |
| P0 | [`b2dd1cc9`][fix-monitor], `default/hypr/monitor-workspaces.lua` | Defers workspace reconciliation until monitor teardown finishes, fixing a compositor-crash path introduced by the new workspace model. Include with that model; do not transplant the feature without the fix. |
| P0 | [`74b3adae`][fix-sshd], `omarchy-setup-security-sshd` | Does not start sshd/open the firewall until a key is authorized. Keep the separately intentional Imager password-auth option explicit; do not accidentally erase it when merging owner setup. |
| P0 | [`8a13eac8`][fix-polkit], [`21e79753`][fix-polkit-migration], migration `1788256455.sh` | Restores system-auth/lockout behavior for the exact old fingerprint/FIDO2 polkit layout and leaves unsuccessful repair pending. |
| P0 | [`87625c2a`][fix-sudo], later [`e9eeba4e`][fix-final-sudo] and final release security files | Bounded passwordless grants and cleanup must be treated as one final-state design with package hooks/scriptlets. The release later uses ordinary sudo timestamps for update authorization; do not describe an intermediate command-scoped design as the released behavior. |
| P1 | [`omarchy-pkgs#937`][fix-voxtype], merge `1d7566acd846f8dcb1438f50a22d6ff910466dfc`, `voxtype-bin.install` | Fixes local-user injection through a predictable `/tmp` backend handoff file during privileged package upgrades. Require the repaired 1.1.1-2 scriptlet or its later equivalent for users retaining Voxtype; it uses root-owned `/run` state and accepts only canonical backend paths under `/usr/lib/voxtype`. The Omarchy source tag alone cannot deliver a package-repository scriptlet fix. |
| P1 | [`6af052fc`][fix-inhibitor], `omarchy-update-stay-awake` | Cleanup acts on the process identity that created the inhibitor, rather than an unrelated reused PID. |
| P1 | [`45a64331`][fix-reset], [`898c42c9`][fix-reset-env], factory reset helpers | Match the installed packaged command and preserve GUM records on elevation. Ext4 Pi still must not advertise a nonexistent Btrfs factory-reset baseline. |
| P1 | [`0d8edf38`][fix-fingerprint], fingerprint removal | Removes reader-resident templates, not only host-side files. Relevant if a supported external reader is used, not grounds to auto-enroll anything. |
| P1 | [`492b8837`][fix-arm-reboot], update restart | Detects installed ARM kernels through `modules.builtin`, avoiding a reboot prompt after every update when there is no `vmlinuz` in the modules directory. |
| P1 | [`3186d180`][fix-lua-tests], Lua test helpers | Ensures Lua assertions actually fail the suite. Preserve this before trusting new workspace/parser fixture results. |
| P1 | [`463a9a1d`][fix-shell-json], shell config | Avoids overwriting an unreadable user `shell.json`. Important during long upgrades and low-memory/disk-pressure conditions. |

Upstream's root-parameter upgrade fix `393a43d4` is also new, but lives in the legacy Quattro transition command. Keep the fork's early ARM refusal there. A 4.0-to-4.5 Pi upgrade must not enter the x86 3-to-4 conversion as a workaround.

Useful Pi efficiency changes include direct shortcuts, direct shell IPC, theme-rendering consolidation, event-driven power/sudo state and reduced idle polling. Take the associated implementation and regression tests; no millisecond, energy or Raspberry Pi OS parity claim is established by this audit.

## Migration ordering and existing-install upgrade sequence

Relative to the common ancestor, the released migration tree has **95 additions, nine modifications and one deletion**. The runner itself is unchanged in the direct fork-to-release comparison. Migrations remain lexically ordered, synchronous, per-user and stopped by failure. Existing user markers prevent a changed old migration from automatically rerunning.

The nine modified filenames are `1785344985`, `1786391100`, `1786605598`, `1786643346`, `1787494718`, `1787580187`, `1787760281`, `1789325478`, and `1790042972` (all `.sh`); `1789091250.sh` is removed. The added `1793069744.sh` explicitly rechecks the older FIDO2 repair, illustrating why edits to already-marked migrations alone cannot deploy a new repair.

| Migration / dependency order | Pi-specific implication |
| --- | --- |
| `1788163635` and `1788256455` | Old sudo grants and polkit repair depend on the matching helpers/security package ownership. Install those before migration execution. |
| `1789325478` | Omarchy kernel installation is x86-only and checks Limine tooling; it should no-op on Pi. Keep that gate. |
| `1789928586` | Only preserves already installed ARM Limine recovery packages when the Limine config exists; it must not install them on Pi. |
| `1790042972` → `1790528634` | Preserve world-clock settings, then change the plugin ID to the in-tree implementation and remove the old package link. |
| `1790539857`, `1790542069`, `1790702362` | Monologue/Hype and compiler/Qt dependencies must be available before the queue reaches them. The application installs honor the preinstalls-removed marker, while compiler/Qt setup is unconditional upstream. |
| `1791345484` | Disktree installation precedes removal of dua-cli and its desktop entry. Do not delete the working tool if the replacement cannot install. |
| `1791403252` → `1791403310` | Repository precedence repair performs another system upgrade, then titlebars install. A Pi policy must handle that nested update and the matching compositor build. With no Omarchy section, the first migration still invokes the system updater. |
| `1791542175` → `1792041364` | First Gliff migration is x86-gated; the later migration explicitly installs it on every aarch64 system. The current Pi unavailable list does not bypass it. |
| `1791554699` | Unconditionally replaces a present stock power daemon with the Omarchy provider, independent of CPPC hardware detection. Decide availability/policy before this step; it calls pacman directly. |
| `1791698594` and `1791708587` | Workspace layout state conversion and Signed install require their new runtime. |
| `1791769486` | Cleans up briefly shipped USB/Thunderbolt authorization state. Preserve its provenance predicates; do not enable that retired feature during integration. |
| `1791968925`, `1791969355` | Tray/center-section layout migrations must run against preserved user config. |
| `1792343099`, `1792343225`, `1792504295` | New mise declarations and shim behavior must already work; preserve explicit user pins and opt-out. |
| `1792648436` | Cleans legacy notification content while preserving DND where needed; run with the new service available. |
| `1793069744` | Rechecks old FIDO2 state even if the older filename is marked complete. Do not fake completion when manual path repair is required. |
| `1793512402`, `1793667581` | XWayland cursor dependency and unfinished Superwhisper user setup also require package/session readiness. |

Do not pre-mark existing users' 95 migrations to force an upgrade through. New users can receive the normal package-seeded marker set because their image already embodies the new state. Corrections to the Pi transition need fresh migration identities or an explicit, tested Pi bootstrap step, consistent with `agents/skills/migrations.md`.

An actionable integration and validation sequence follows. These are proposed future steps; none was executed in this audit.

1. **Freeze inputs.** Preserve `393f48c3`, exact release commit, reviewed core-recipe SHA, selected runtime closure and source overrides. Record package database hashes and archive/signature identities. Inventory representative original-image and current-alpha update starting points.
2. **Establish focused baseline tests.** Run existing Pi update/provisioning/package/graphics fixtures before edits, using Bash 5 and no live hardware mutation. Keep test output outside source payloads.
3. **Resolve repository policy first.** Implement an architecture/channel-aware Pi package resolver and protect the local core pair from official replacement. Preserve source origin/main/clean-tree checks and signature policy. Make render/refresh/setup/update paths agree.
4. **Adapt and inspect recipes.** Build the local pair with the new ownership/scriptlet contract in a disposable ARM Linux environment; inspect archive paths, metadata, backup entries, hooks and generated settings. Do not install generic boot fragments, whole-RAM/zstd policy or duplicate-owned sudo helpers.
5. **Resolve runtime before user state.** Upgrade minimum mise and required libraries; arrange matching Hyprland/titlebars, patched Quickshell/Qt, speedtest, realtime audio and package-backed application migrations. Avoid dependency replacement after migrations start.
6. **Merge the exact source tag.** Resolve the 13 predicted text conflicts and seven additional semantic overlaps. Retain the complete Pi-only path inventory. Port the final release fixes and matching tests together.
7. **Reconcile new desktop costs.** Keep tiling as the initial Pi layout; preserve no-blur/low-effect defaults, static backgrounds and administrator display overrides. Explicitly handle floating-mode shadows and optional intro downloads. Do not enable overclocking or force GPU/CMA memory settings.
8. **Adapt fresh-image setup.** Compose base+ARM additions with the Pi exclusions; stop silently skipping required packages. Preserve verified offline Node staging, root-growth-before-owner, SDDM/Avahi ordering, per-device keyring initialization, secret cleanup and deterministic provenance.
9. **Define bootstrap for existing images.** Use the fork's reviewed fast-forward-only bootstrap pattern. The running old updater and pre-transaction hooks do not magically gain new logic when files are replaced. A staged handoff must use the current guards without resetting configuration or replaying owner setup.
10. **Perform the package transition on a disposable installation copy.** Capture the full solver transaction, configs and boot artifacts. Check one coherent system/library/compositor transition, install local core/settings together, and retain recovery archives. Treat conflicts or unresolved signatures as failure.
11. **Restart/hand off safely.** Keep live-config reload paused around replacement, avoid loading successor config into an old replaced Hyprland, and start the matching shell before migration IPC. Do not interrupt a live secure lock client. If no session is available, retain pending work and complete/verify it on the next appropriate session.
12. **Run pending migrations in filename order.** Fail and retry at the first unresolved package/state repair. Validate both an ordinary desktop update and the supported SSH/headless boundary. Do not equate an advanced Git HEAD or successful core receipt with successful migrations.
13. **Finish the update pipeline.** Preserve post-update hooks and AUR/mise error handling, the owned sleep inhibitor, safe orphan cleanup, service restart and reboot phases. Add actual Pi boot verification before presenting an update as complete; upstream generic ARM verification is a no-op.
14. **Audit the finished image.** Run the existing rootfs gate and ARM Hyprland config verifier against the new package set. Extend them for patched Quickshell/Qt, plugin/package pairing and effective Pi policies; fail on missing required features even if Lua parsing succeeds.
15. **Validate physical Pi 4.** Boot and test stock-clock 4GB first, then 8GB. Only after running-desktop, hardware and existing-install transition evidence should support claims and release notes advance. Pi 5 needs separate bring-up later.

## Verification gates and remaining evidence

Project guides read: command metadata, install scripts, shell development, migrations, acceptance tests, visual verification, and testing documentation; the release's additional mise guide was also inspected. Their boundaries remain appropriate: headless fixtures, assembled-image checks, graphical acceptance and physical-board validation answer different questions.

Before implementation is considered complete:

- Run focused existing tests for `rpi-update-safety`, `rpi-upgrade-guide`, `raspberry-pi`, `rpi-optimization`, `rpi-performance`, `rpi-firmware`, `rpi-hyprland-verify`, `rpi-grow-root`, `rpi-imager-preseed`, `rpi-owner-hostname`, `rpi-display`, `rpi-tune` and screensaver behavior. Invoke individual files with Bash 5 for focused work; `test/shell` does not accept a filename filter. The incoming aggregate runner uses `nproc` parallelism, so account for memory contention on the Pi when running it.
- Add behavioral coverage for effective zram merging (including the vendor compressor), no generic boot payload, version-aware mise upgrade, matched titlebar ABI, protected local core packages, new migration packages, stale updater/shell handoff, failure/retry after a source advance, and offline first boot. These are high-impact integration boundaries, not implementation-mirroring tests.
- Run `./test/cli` and the appropriate shell aggregate after focused checks. Preserve upstream's Lua assertion failure fix and distinguish skips from passes. No test suite was run in this research assignment.
- On the assembled Linux image, inspect actual package ownership and file lists, run `image/audit-rpi4-rootfs.sh` and `image/verify-rpi4-hyprland.sh`, and retain package/source manifests. Add a real shell load/panel exercise in the disposable graphical environment; parse success alone cannot validate a lazy titlebar load or Qt import behavior.
- Follow `agents/skills/acceptance-tests.md`: graphical acceptance belongs in a disposable VM rather than the active development desktop. A VM cannot prove V3D/VC4 scanout, Pi HDMI/audio, firmware or Cortex-A72 instruction compatibility.
- On actual Pi 4, require boot-to-owner/login, correct Imager hostname and keymap, offline provisioning, wired/Wi-Fi/mDNS/SSH policy, Bluetooth pairing, HDMI modes, actual accelerated renderer, sound playback, lock/unlock/wake, floating/dock/minimize/restore, dual-monitor disconnect/reconnect, screenshot, recording with audio, representative applications, and an existing-install update/retry. Inspect screenshots/video as required by the visual-verification guide.
- Record idle/load CPU, available memory/PSI, effective zram compressor/size, oomd app-scope policy, governor, temperatures/voltage alarms, frame responsiveness, and image/package versions. Compare stock clocks and identical workloads before claiming gains or Raspberry Pi OS parity. Existing diagnostics/resource budgets are already present and should be used.
- Keep Paper Mono as the user's requested UI font if typography is changed, with official assets/license and appropriate fallbacks. Preserve the separately required branded/Nerd icon glyph fonts. This audit did not add font assets or change UI typography.

Open facts requiring Linux/runtime or hardware evidence: final dependency-solver closure, binary signature trust, actual titlebar build compatibility, runtime Qt private-ABI behavior, selected kernel zram algorithms, new kernel/firmware boot and HDMI behavior, vendor-binary Cortex-A72 compatibility, local dictation cost, recording/video decode acceleration, and 4GB/8GB performance. The pending hardware-access question is outside this report; nothing here claims that it has been answered.

## Pi-protected path inventory

The inventory below is generated from `git diff --name-only d3cfd53b997f8bdcf776b8db68bf0d735e7a065d 393f48c3`, not a proposed set of files to reset wholesale. It lists all 111 paths representing the fork's changes from the common ancestor. Preserve their responsibilities, while merging newer shared implementations where appropriate. Additional new upstream files with Pi-sensitive assumptions are described above.

```text
.github/CODEOWNERS
.github/ISSUE_TEMPLATE/bug.yml
.github/ISSUE_TEMPLATE/config.yml
.github/SECURITY.md
.github/workflows/build-rpi4-image.yml
.github/workflows/pi-checks.yml
.gitignore
README.md
bin/omarchy
bin/omarchy-apply-pi-performance
bin/omarchy-capture-screenrecording
bin/omarchy-channel-current
bin/omarchy-channel-set
bin/omarchy-hw-raspberry-pi
bin/omarchy-pi-benchmark
bin/omarchy-pi-check
bin/omarchy-pi-cpu-policy
bin/omarchy-pi-display
bin/omarchy-pi-report
bin/omarchy-pi-run
bin/omarchy-pi-status
bin/omarchy-pi-tune
bin/omarchy-provision-owner
bin/omarchy-refresh-limine
bin/omarchy-refresh-pacman
bin/omarchy-remove-gaming-retroarch
bin/omarchy-rpi4-grow-root
bin/omarchy-rpi4-imager-preseed
bin/omarchy-screensaver
bin/omarchy-update
bin/omarchy-update-aur-pkgs
bin/omarchy-update-available
bin/omarchy-update-confirm
bin/omarchy-update-dev
bin/omarchy-update-keyring
bin/omarchy-update-rpi4
bin/omarchy-update-rpi4-guard
bin/omarchy-update-system-pkgs
bin/omarchy-upgrade-to-quattro
bin/omarchy-version-channel
build-packages-rpi4.sh
default/hypr/envs.lua
default/hypr/raspberry-pi.lua
default/omarchy/omarchy-menu.jsonc
default/pacman/mirrorlist-rpi4
default/pacman/mirrorlist-rpi4-image
default/pacman/pacman-rpi4.conf
default/pi/benchmark.py
default/pi/build-budget.sh
default/pi/journald.conf
default/pi/makepkg.conf
default/pi/oomd.conf
default/pi/sysctl.conf
default/pi/tune.py
default/pi/zram.conf
docs/assets/hero-art-direction.md
docs/assets/hero-placeholder.svg
docs/assets/hero.png
docs/assets/imager-icon.svg
docs/pi-performance.md
docs/pi-tuning.md
docs/pi-upgrade.md
docs/pi4-hardware-follow-up.md
docs/raspberry-pi-4.md
docs/releases/v0.1.0-rc.1.md
docs/releases/v0.2.0-alpha.2.md
docs/releases/v0.2.0-alpha.4.md
docs/rpios-driver-audit.md
image/Dockerfile.builder
image/audit-rpi4-rootfs.sh
image/build-rpi4-image-macos.sh
image/build-rpi4-image.sh
image/generate-imager-catalog.sh
image/generate-local-imager-manifest.sh
image/inspect-rpios-driver-packages.sh
image/omarchy-pkgs.commit
image/open-in-rpi-imager-macos.sh
image/prepare-release-assets.sh
image/validate-imager-catalog.sh
image/verify-rpi4-hyprland.sh
install-rpi4.sh
install/config/snapper.sh
install/hardware/all.sh
install/hardware/apple/fix-spi-keyboard.sh
install/hardware/raspberry-pi.sh
install/omarchy-rpi4-unavailable.packages
install/post-install/pacman.sh
install/provisioning/omarchy-avahi-rpi4.conf
install/provisioning/omarchy-pi-cpu-policy.service
install/provisioning/omarchy-pi-tune-guard.service
install/provisioning/omarchy-provision-owner-rpi4.conf
install/provisioning/omarchy-rpi4-grow-root.service
install/provisioning/omarchy-sddm-rpi4.conf
install/user/mise-work.sh
manual/pi.md
test/shell.d/fixtures/pi-tune-test.py
test/shell.d/provision-user-test.sh
test/shell.d/raspberry-pi-test.sh
test/shell.d/rpi-display-test.sh
test/shell.d/rpi-firmware-test.sh
test/shell.d/rpi-grow-root-test.sh
test/shell.d/rpi-hyprland-verify-test.sh
test/shell.d/rpi-imager-preseed-test.sh
test/shell.d/rpi-optimization-test.sh
test/shell.d/rpi-owner-hostname-test.sh
test/shell.d/rpi-performance-test.sh
test/shell.d/rpi-tune-test.sh
test/shell.d/rpi-update-safety-test.sh
test/shell.d/rpi-upgrade-guide-fixture.py
test/shell.d/rpi-upgrade-guide-test.sh
test/shell.d/screensaver-test.sh
```

## Primary source links

Links are attached near the findings above; definitions below keep the audit's source identities readable. Live repository databases are mutable and should be replaced with recorded hashes in the implementation's package lock.

[fix-voxtype]: https://github.com/omacom/omarchy-pkgs/pull/937
[release]: https://github.com/omacom/omarchy/releases/tag/v4.5.0
[tag-commit]: https://github.com/omacom/omarchy/commit/ac2690cd7be4f47e4a255f5e2e78d904d436b068
[announcement]: https://omarchy.org/news/2026/11/omarchy-4-5/
[old-recipes]: https://github.com/omacom/omarchy-pkgs/commit/99234a4fbb61b46225b2e9e560e114fbfebe8a95
[old-core]: https://github.com/omacom/omarchy-pkgs/blob/99234a4fbb61b46225b2e9e560e114fbfebe8a95/pkgbuilds/omarchy/PKGBUILD
[old-settings]: https://github.com/omacom/omarchy-pkgs/blob/99234a4fbb61b46225b2e9e560e114fbfebe8a95/pkgbuilds/omarchy-settings/PKGBUILD
[new-core]: https://github.com/omacom/omarchy-pkgs/blob/c7a1ef7f86cccab072fb11f22564862c03f50199/pkgbuilds/omarchy/PKGBUILD
[new-settings]: https://github.com/omacom/omarchy-pkgs/blob/c7a1ef7f86cccab072fb11f22564862c03f50199/pkgbuilds/omarchy-settings/PKGBUILD
[new-scriptlet]: https://github.com/omacom/omarchy-pkgs/blob/c7a1ef7f86cccab072fb11f22564862c03f50199/pkgbuilds/omarchy-settings/omarchy-settings.install
[recipe-source-compare]: https://github.com/omacom/omarchy/compare/a948d8a6871f446b335258c827648ac5f4e9428b...ac2690cd7be4f47e4a255f5e2e78d904d436b068
[stable-hypr-recipe]: https://github.com/omacom/omarchy-pkgs/blob/ebedd694af9f5c715b9761a917fde9da2b4f2262/pkgbuilds/hyprland/PKGBUILD
[stable-titlebars-recipe]: https://github.com/omacom/omarchy-pkgs/blob/c4474ede2e92cf592c4dfc74c0d208d0af967e95/pkgbuilds/omarchy-hyprland-titlebars/PKGBUILD
[stable-quickshell-recipe]: https://github.com/omacom/omarchy-pkgs/blob/2be7cd983944f50612338124ec6725da95dceb2e/pkgbuilds/quickshell/PKGBUILD
[quickshell-patch]: https://github.com/omacom/omarchy-pkgs/blob/2be7cd983944f50612338124ec6725da95dceb2e/pkgbuilds/quickshell/load_qtquick_611.patch
[superwhisper-recipe]: https://github.com/omacom/omarchy-pkgs/blob/c7a1ef7f86cccab072fb11f22564862c03f50199/pkgbuilds/superwhisper-bin/PKGBUILD
[quickshell-guide]: https://quickshell.org/docs/guide/install-setup/
[hypr-env]: https://wiki.hypr.land/configuring/core/environment-variables/
[alarm-pi4]: https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4
[platform-detector]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/bin/omarchy-hw-platform
[pacman-helper]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/install/helpers/pacman.sh
[runtime-profile]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/default/settings-runtime-profile
[mkinit-baseline]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf
[lifecycle-dispatch]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/bin/omarchy-lifecycle-dispatch
[update-boot]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/bin/omarchy-update-boot
[sudo-source]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/bin/omarchy-sudo-passwordless
[mise-guide]: https://github.com/omacom/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/agents/skills/mise-tools.md
[zram-doc]: https://github.com/systemd/zram-generator/blob/main/man/zram-generator.conf.md
[stable-db]: https://pkgs.omarchy.org/stable/aarch64/omarchy.db
[alarm-extra]: https://fl.us.mirror.archlinuxarm.org/aarch64/extra/extra.db
[stable-arm-extra]: https://arm-stable-mirror.omarchy.org/aarch64/extra/extra.db
[pkgs-builder]: https://github.com/omacom/omarchy-pkgs/blob/c7a1ef7f86cccab072fb11f22564862c03f50199/build/Dockerfile
[fix-migration-shell]: https://github.com/omacom/omarchy/commit/3e634acf9a60467a9f77bd732d087bde35533945
[fix-reload]: https://github.com/omacom/omarchy/commit/81d0bc90d856a8b1c46259bafd5ea3fbe5a023de
[fix-monitor]: https://github.com/omacom/omarchy/commit/b2dd1cc9016ab389641de1020c64417802be7619
[fix-sshd]: https://github.com/omacom/omarchy/commit/74b3adaeef2464edd8845012a3a46d5788b8d829
[fix-polkit]: https://github.com/omacom/omarchy/commit/8a13eac872988c722be4cb4765211593b61d6de9
[fix-polkit-migration]: https://github.com/omacom/omarchy/commit/21e7975352da486e2ff30820a9abab4c020fa28e
[fix-sudo]: https://github.com/omacom/omarchy/commit/87625c2ad8cf0e0bc08676127548a532d318036e
[fix-final-sudo]: https://github.com/omacom/omarchy/commit/e9eeba4e501aeb7c00cdc30fd3086c4b466cb3bc
[fix-inhibitor]: https://github.com/omacom/omarchy/commit/6af052fcc3c68f2fe4a3cdbcb9afbd2bc780c48c
[fix-reset]: https://github.com/omacom/omarchy/commit/45a64331394f62b0b853bf5a14805f94e66bdc7c
[fix-reset-env]: https://github.com/omacom/omarchy/commit/898c42c9b18865eb7336c7bc8eb314a2e47471e3
[fix-fingerprint]: https://github.com/omacom/omarchy/commit/0d8edf3812e0caafd155760c96bc2862933f611a
[fix-arm-reboot]: https://github.com/omacom/omarchy/commit/492b8837deea69663c7a5418871f07ed075a9686
[fix-lua-tests]: https://github.com/omacom/omarchy/commit/3186d18026638d7be95691f116f8389e92bc0b73
[fix-shell-json]: https://github.com/omacom/omarchy/commit/463a9a1d28d45e9c4714286745023272fc23fde7
