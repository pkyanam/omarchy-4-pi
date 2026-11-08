# PI-019: screensaver cropping investigation and source candidate

Status: user-reported, not physically reproduced by this lane. November 8, 2026. No Pi/SSH access, installation, screenshots, performance measurement, staging, commits, pushes, PRs, or external messages were performed. The parent owns physical acceptance. Complete normal sources were available; reverse-engineer-anything was not needed or invoked.

## Finding and implementation ownership

The supplied installed versions are screensaver 1.3.1-1 and runtime/settings 4.5.0-2.6, source `0254fe47c17647ba84d16d3b571015451da794a4`, at HDMI 1024×768@60.004, scale 2 (512×384 logical). Missing EDID/fallback modes are context, not proof of a screensaver scaling bug.

**An installed native screensaver package does not establish that the native renderer is launched.** The local exact 2.6 package contains the terminal launcher from the stable source. The packaged `/usr/bin/omarchy-launch-screensaver` and pristine stable launcher both hash to SHA-256 `4583e38389c1e46604f59dd83f21b4da9be4de1c66157299e13748fe1d0709b0`. Checked package: `build/upstream-pi/stable-4.5/preview-rollback-candidate/omarchy/omarchy-4.5.0-2.6-aarch64.pkg.tar.zst`. Parent still must confirm the live executable/PATH has not been overridden.

Stable launch path: idle/menu → `omarchy-launch-screensaver` → selected Alacritty/Ghostty/Foot/Kitty, class `org.omarchy.screensaver`, special workspace per monitor → `omarchy-screensaver` → `ttfx` branding animation. The command reads `~/.config/omarchy/branding/screensaver.txt`, uses random effects, terminal-sized canvas, centered text/canvas, and retains its input/focus dismissal behavior. All four terminals originally use 18 pt. Stable settings seed the 80-column, 10-line `logo.txt` into that branding file. The native archive's much smaller bundled sample is not the stable installed default logo.

At standard 96 DPI, 18 pt is 24 logical pixels tall in font units. JetBrains Mono's nominal 0.6-em advance gives 14.4 logical pixels per column, rounded by the terminal. An 80-column logo needs approximately 1152 logical pixels of width, against 512 available. Roughly 35 columns fit at that size. Centered text loses substantial left/right content: this is a concrete source-supported failure mechanism, not evidence of physical reproduction or proof that the user's “image” is this branding. Even scale 1 at 1024 pixels can clip this logo.

The owning implementation for this installed lineage is `/Users/preetham/Code/omarchy-upstream-pi-stable/bin/omarchy-launch-screensaver`. The package recipe is `/Users/preetham/Code/omarchy-pkgs-pi/pkgbuilds/omarchy/PKGBUILD`; it installs `bin/*` as `/usr/bin/*`. The local candidate's recipe uses the stable source override. Shared runtime/settings recipes were not edited.

## Complete source provenance and native renderer cross-check

Package repo inspected at `474cdba825e630250f9b82b8b0055b5ecb594da3`. Its `pkgbuilds/omarchy-screensaver/PKGBUILD` builds the complete [omacom/omarchy-screensaver v1.3.1 source](https://github.com/omacom/omarchy-screensaver/tree/v1.3.1), not a vendor binary. Fetched tag archive SHA-256 `7bd9b75abc4fea072f63dec3a8fc339eee282bd1aca148a27a979766b657ff61` matches the recipe exactly. Annotated tag object `19cbe9cbcb7160a3931901aebc167da0c42ece38` peels to source commit `b3026b63999908bf424eae62194aa95df5e4d24c`. Cargo.lock is present; the recipe fetches locked dependencies and builds frozen/release. It renames `target/release/omarchy-launch-screensaver` to `/usr/lib/omarchy-screensaver/omarchy-screensaver`.

The native Cargo.lock pins [ttfx v0.5.1](https://github.com/omacom/ttfx/tree/14ed2742596f0056b13e25d14a83ea851adc2294), commit `14ed2742596f0056b13e25d14a83ea851adc2294`. The separate ttfx package recipe also builds 0.5.1; downloaded archive SHA-256 `3f10b987b7690aa3caa2fa4f1749d8c7904e177380eff3e000d3422da8eb0134` matches that recipe. This establishes recipe-to-complete-source provenance, not live binary reproducibility or the currently installed ttfx version, which parent must record.

Native implementation: `src/wayland.rs` creates one layer surface per output, derives physical buffer dimensions as logical configure size × integer output scale, sets `wl_surface.set_buffer_scale(scale)`, and passes physical dimensions/scale to `Rasterizer::grid_size`. `src/raster.rs` divides physical dimensions by scaled cell metrics and scales glyph rasterization once. Thus the two multiplications implement buffer allocation and glyph density in physical pixels; the compositor divides buffer dimensions by scale. No extra factor-of-two zoom is established by this code. Native fixed 24-logical-pixel fonts can also overflow wide branding. Its shared largest-output animation grid additionally merits smaller-secondary-output testing, but this lane does not change an unselected renderer or replace the stable architecture.

The newer sibling `/Users/preetham/Code/omarchy-upstream-pi` at `a94119ebc3c791cc3aa246da9aa519dd800f6398` uses `exec /usr/lib/omarchy-screensaver/omarchy-screensaver "$@"`. That is a different launch architecture from installed 2.6. Do not apply the stable launcher change blindly to that branch.

Local downloaded source archives, extracted complete sources, and pristine stable launcher are under ignored `build/upstream-pi/stable-4.5/screensaver-audit/`. No shipped-artifact source gap justifies binary decompilation here.

## Candidate source change

Changed only the stable screensaver launcher and its existing `test/shell.d/screensaver-workspace-test.sh`. Before each monitor launch, choose a point size from branding width/height and logical monitor dimensions, with one-cell edge allowance, rounding/line-spacing headroom, 1 pt lower bound and existing 18 pt upper bound. Divide physical dimensions by scale once; swap width/height for odd output transforms. Expand tabs conservatively to four spaces when counting the plain-text branding. Pass size through each terminal's existing CLI configuration mechanism. No effect/filter, canvas, input, multi-monitor workspace, cursor, or dismissal behavior is removed.

Default-logo fixtures select 7 pt at 1024×768/2× and 18 pt at 3840×2160/2×. This is a bounded font-sizing candidate, using nominal JetBrains Mono metrics with headroom (0.85 logical px/pt width, 1.9 height), not exact measurement of every terminal/font. Custom fonts, terminal DPI overrides, Unicode-wide/combining characters, escape sequences, extreme branding larger than the 1 pt floor, and live resolution changes after launch require further qualification. Fit at launch is the scope; no resize watcher or polling was added. Existing project-specific font choices are preserved.

Terminal options checked against [Alacritty configuration](https://alacritty.org/config-alacritty.html), [Ghostty font-size reference](https://ghostty.org/docs/config/reference#font-size), [Foot CLI manual](https://man.archlinux.org/man/foot.1.en), and [Kitty CLI](https://sw.kovidgoyal.net/kitty/invocation/). CLI propagation tests do not substitute for launching these real terminals.

## Focused regression evidence

The existing workspace test now uses the real default branding and small/large monitor geometry, exercising real launch-command construction. It catches regression to a fixed 18 pt font while retaining workspace and focus coverage. No new test file or mirrored implementation was added.

- Patched Foot test: `/tmp/omarchy-screensaver-fit.log`, seven checks pass.
- Alacritty/Ghostty/Kitty: `/tmp/omarchy-screensaver-fit-Alacritty.desktop.log`, `/tmp/omarchy-screensaver-fit-ghostty.desktop.log`, `/tmp/omarchy-screensaver-fit-kitty.desktop.log`; seven checks pass per terminal selection.
- Pristine launcher with the new test: `/tmp/omarchy-screensaver-fit-base.log`, fails specifically at “small 2x output fits branding”. An initial attempt could not execute the saved pristine file (mode lacked execute); corrected the local saved file mode before this substantive red result.
- `bash -n` passed for changed launcher. Tests ran in existing `omarchy-pi-test:4.5` container, network disabled, 0.25 CPU/128 MiB; no image/package compilation. No broad suite needed for this screensaver-only change.

## Parent reproduction and acceptance procedure

1. In the authorized live desktop session, record `pacman -Q omarchy omarchy-settings omarchy-screensaver ttfx`, `type -a omarchy-launch-screensaver omarchy-screensaver ttfx`, `sha256sum /usr/bin/omarchy-launch-screensaver`, `xdg-terminal-exec --print-id`, and `hyprctl monitors -j`. Inspect the live launcher with `sed -n '1,100p' /usr/bin/omarchy-launch-screensaver` to distinguish terminal/native launch. Record selected terminal version and `fc-match monospace`. Record the actual branding dimensions/content privately; do not assume the default logo or publish personalized content.
2. Preserve normal idle/lock state and baseline 1024×768@60.004/scale 2. Have the desktop unlocked and active, launch `omarchy-launch-screensaver force`, capture a short fullscreen recording through the parent-owned capture path, and dismiss with a key. Inspect completion/settled frames as well as transitions: many effects intentionally move characters beyond their final positions. Inspect process argv while running to confirm the selected renderer. Retain baseline images privately.
3. Use the actual branding and a controlled plain-text border fixture with distinctive four corners. For the terminal path, a deterministic settled render can be inspected in the same screensaver terminal configuration using `ttfx -i /path/to/border.txt --canvas-width 0 --canvas-height 0 --anchor-canvas c --anchor-text c --no-eol --no-restore-cursor print`. First verify installed `ttfx --help` supports that invocation. Also run the normal random-effects screensaver to preserve real launch/dismissal acceptance. Do not infer fit from a transient transition frame.
4. Review the candidate diff in the stable repo. For a reversible no-package trial, copy only the candidate launcher to a parent-chosen temporary executable path on the Pi (no config overwrite), then run that absolute path with `force` inside the existing session. Its launched child remains the installed `omarchy-screensaver`, so this isolates launcher font sizing. Record command argv/font size and compare settled content/border corners at the identical monitor state. Delete the temporary candidate afterward. No shell restart or monitor-scale change is needed. If integrating later, parent owns paired runtime/settings packaging/versioning; do not build now against H264's budget.
5. Require all default-branding edges and four border corners visible at scale 2, centered, without stretched glyphs. Verify keyboard, mouse movement/click/scroll dismissal, cursor restoration, screensaver-off/force behavior, monitor focus restoration, and special-workspace preservation. Test available terminal selections and any rotated/secondary displays; test larger geometry retains ordinary size. Avoid changing the user's default terminal/config just to exercise absent terminals.
6. Recheck monitor state and idle policy after trials; restore anything the parent changed. Keep full before/after screenshots and a short animation recording, inspect them per `agents/skills/visual-verification.md`, and explicitly record pass/fail. Source tests here cannot close that required gate.

### Exact session-side trial commands

Parent transfers the candidate launcher to `/tmp/omarchy-launch-screensaver-fit-candidate` using its authorized transport, then runs these in the unlocked desktop environment. The capture/recording tools stay parent-owned. Do not run the candidate concurrently with the baseline.

```bash
chmod 755 /tmp/omarchy-launch-screensaver-fit-candidate
pacman -Q omarchy omarchy-settings omarchy-screensaver ttfx
type -a omarchy-launch-screensaver omarchy-screensaver ttfx
sha256sum /usr/bin/omarchy-launch-screensaver
xdg-terminal-exec --print-id
hyprctl monitors -j
omarchy-launch-screensaver force
# Parent captures baseline, then dismisses it with input.
/tmp/omarchy-launch-screensaver-fit-candidate force
# Parent captures candidate, then dismisses it with input.
hyprctl monitors -j
rm /tmp/omarchy-launch-screensaver-fit-candidate
```

For the controlled terminal-content trial, create a plain 80×10 border without touching the user's branding:

```bash
awk 'BEGIN { for (r=0; r<10; r++) { for (c=0; c<80; c++) printf "%s", (r==0 || r==9 || c==0 || c==79) ? "#" : " "; printf "\n" } }' > /tmp/omarchy-screensaver-border.txt
```

Use `--input` only on the native executable; the stable wrapper does not forward it. For stable terminal comparison, launch the selected terminal with the baseline screensaver options and the `ttfx -i /tmp/omarchy-screensaver-border.txt ... print` command from step 3, then repeat with the candidate's font-size option (7 pt for this fixture/output). Keep the same `org.omarchy.screensaver` class/fullscreen rule and manually dismiss the terminal after the capture. This controlled trial validates font/grid behavior separately from the normal command's random effects.

## Aspect crop versus defect

Neither the stable terminal branding path nor native v1.3.1 decodes wallpaper images/video or exposes contain/cover modes. These are character-cell animations, not aspect-ratio image fitting. A missing edge in a settled text border is clipping, not an expected wallpaper cover effect. At most, intermediate offscreen animation motion is intentional.

If the user's “image” is instead a wallpaper, slideshow, lock-screen background, or Amiga demo, record the actual process/surface and input asset before applying this candidate. Those paths are not established by the screensaver package version and were not changed here. A genuine cover policy uses max(viewportWidth/imageWidth, viewportHeight/imageHeight), so a 16:9 image covering 4:3 loses 25% of source width in total (12.5% per side when centered); contain shows all edges with letterboxing. Excess beyond that geometry, or cropping a matching-aspect border fixture, warrants a separate defect diagnosis. This distinction does not dismiss PI-019.

Physical reproduction and visual candidate acceptance remain pending with the parent. No performance benefit or final user-visible repair is claimed.

## Parent integration checkpoint

Parent reviewed and committed the launcher/test change locally in the stable owning repository as `30ba85096`. This report is preserved in the integration ledger. Installed runtime/settings 2.6 predate that commit; no package or physical screensaver fix is claimed. The desktop remains locked as of the 12:12 UTC headless checkpoint, and the pending owner unlock gates visual acceptance.
