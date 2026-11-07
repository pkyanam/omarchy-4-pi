"""Seed conservative defaults once for a fresh Pi account, before theme setup."""

import json
import os
from pathlib import Path
import sys


def write_new(path, data):
  path.parent.mkdir(parents=True, exist_ok=True)
  try:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
  except FileExistsError:
    return
  with os.fdopen(descriptor, "wb") as stream:
    stream.write(data)


def seed(source, home):
  state = home / ".local/state/omarchy"
  marker = state / "done/pi-user-defaults"
  # A saved theme is already a choice, even if finalization later failed. The
  # leaf runs before theme.sh and never reapplies a removed toggle on retry.
  if any(os.path.lexists(path) for path in (marker, state / "done/finalize-user", state / "current/theme.name", state / "current/background")):
    return
  write_new(state / "toggles/hypr/no-animations.lua", (source / "default/hypr/toggles/no-animations.lua").read_bytes())
  write_new(state / "toggles/background-intros-off", b"")
  # The stock first Tokyo Night image is static. Remember it through the same
  # interface theme-set uses, so directory ordering can never choose a video.
  background = source / "themes/tokyo-night/backgrounds/0-liftoff.webp"
  if not background.is_file():
    raise ValueError("The Pi default static wallpaper is missing.")
  write_new(state / "theme-backgrounds/tokyo-night", (str(state / "current/theme/backgrounds" / background.name) + "\n").encode())

  shell = home / ".config/omarchy/shell.json"
  shipped_shell = (source / "config/omarchy/shell.json").read_bytes()
  if not os.path.lexists(shell):
    data = json.loads(shipped_shell)
    data.setdefault("bar", {})["background"] = "opaque"
    write_new(shell, (json.dumps(data, indent=2) + "\n").encode())
  # Already-seeded shell.json is opaque upstream; never rewrite a custom bar
  # or its dock layout just to force this preset on someone else's choices.

  fontconfig = home / ".config/fontconfig/fonts.conf"
  if not os.path.lexists(fontconfig):
    font_source = source / "default/pi/fonts/paper-mono"
    for path in sorted(font_source.iterdir()):
      if path.suffix == ".ttf" or path.name == "OFL.txt":
        write_new(home / ".local/share/fonts/paper-mono" / path.name, path.read_bytes())
    write_new(fontconfig, (source / "default/pi/fonts.conf").read_bytes())
    # Change only byte-for-byte shipped terminal defaults. Custom size, family,
    # style or other terminal preferences are evidence of an owner's choice.
    for relative in ("foot/foot.ini", "ghostty/config", "alacritty/alacritty.toml", "kitty/kitty.conf"):
      target = home / ".config" / relative
      baseline = source / "config" / relative
      if target.is_file() and not target.is_symlink() and target.read_bytes() == baseline.read_bytes():
        text = target.read_text().replace("JetBrainsMono Nerd Font", "Paper Mono")
        if relative == "foot/foot.ini":
          text = text.replace("font=Paper Mono:size=9", "font=Paper Mono:size=9,JetBrainsMono Nerd Font:size=9")
        target.write_text(text)
  write_new(marker, b"")


if __name__ == "__main__":
  seed(Path(sys.argv[1]), Path(sys.argv[2]))
