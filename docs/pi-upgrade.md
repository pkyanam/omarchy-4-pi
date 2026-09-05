# Updating an existing Pi without reflashing

Normal updates use `omarchy update`. This port follows `pkyanam/omarchy-4-pi`, `origin/main`; it is not a release-tag selector. Arch Linux ARM system packages also move forward. The latest alpha image and a fully updated existing installation therefore need not contain identical package versions.

Back up important files or the whole card first. This ext4 installation has no automatic pre-update snapshot. Keep reliable power connected, close large browser/build workloads, and do not interrupt package installation. A failed update must be investigated and retried, not followed by an immediate reboot.

## Original general release: one-time updater bootstrap

The original `v0.1.0-rc.1` image contains an older updater. Its first core rebuild does not reconcile the new runtime dependencies or apply the new Pi defaults; it may also lack the factory's temporary package-recipe checkout. Merely running that old updater once is not a complete upgrade to the new Pi features.

On an unmodified original-image source checkout, the following launches the current updater directly from this fork. It verifies the repository, branch, upstream, and clean working tree before fetching. It does not re-run first-boot setup, reset the hostname, replace your display profile, or enable overclocking. Run as your normal desktop user in an interactive terminal, not with `sudo` around the whole command:

```bash
bash -c '
set -euo pipefail
checkout=/opt/omarchy-4-pi
refuse() { echo "Upgrade stopped: $*" >&2; exit 1; }
[[ -d $checkout/.git ]] || refuse "the original-image checkout is missing"
case "$(git -C "$checkout" remote get-url origin)" in
  https://github.com/pkyanam/omarchy-4-pi|https://github.com/pkyanam/omarchy-4-pi.git|git@github.com:pkyanam/omarchy-4-pi.git) ;;
  *) refuse "unexpected repository; do not replace it blindly" ;;
esac
[[ $(git -C "$checkout" symbolic-ref --quiet --short HEAD) == "main" ]] || refuse "expected main"
[[ $(git -C "$checkout" rev-parse --abbrev-ref --symbolic-full-name @{upstream}) == "origin/main" ]] || refuse "expected origin/main tracking"
[[ -z $(git -C "$checkout" status --porcelain) ]] || refuse "preserve your local source changes first"
git -C "$checkout" fetch origin refs/heads/main:refs/remotes/origin/main
git -C "$checkout" merge --ff-only origin/main
export PATH="$checkout/bin:$PATH"
export MAKEFLAGS="${MAKEFLAGS:--j2}" CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}" CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
"$checkout/bin/omarchy-update"
'
```

Stop if a check fails. Do not use `git reset --hard`, change the remote, or remove your edits just to bypass it. The updater performs additional ARM/package-channel checks and asks for normal update/sudo confirmation. This is a source/package rebuild, not a quick image download; it can take time on a 4GB Pi. If it fails after the checkout advances, the same bootstrap can retry: the new updater records successful package installation separately from the Git commit.

The bootstrap preflight and handoff are fixture-tested; the full upgrade from a user's original SD card is not yet hardware-validated. Keep your working-card backup. Reflashing a spare card remains the way to test the exact factory image and first-boot behavior.

## After a successful update

Reboot when the update offers it, then check:

```bash
hostnamectl --static
omarchy-pi-check
omarchy pi report --json
zramctl
systemctl --failed
```

The new CPU, compressed-swap, logging, and writeback policies take effect at boot. Existing owner provisioning and display customization are not replayed. Clock trials are still a separate, explicit operation; read [tuning and recovery](pi-tuning.md) first. Future updates use the ordinary `omarchy update` command.
