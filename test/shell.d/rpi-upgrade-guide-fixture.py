"""Exercise transition refusals using the real updater/installer leaves.

A legacy updater may already have fetched new source before sourcing installer
helpers. That path must still refuse before recipe/trust/package mutation.
Candidate/dirty images must also fail the normal updater before source fetch.
Nothing in this fixture downloads or runs a mutable bootstrap from the guide.
"""
from pathlib import Path
import os
import shlex
import shutil
import subprocess
import tempfile


repo = Path(os.environ["ROOT"])
bash = os.environ["RPI_TEST_BASH"]
real_git = shutil.which("git")
if real_git is None:
  raise SystemExit("git is required")


def check(condition, description, detail=""):
  if not condition:
    raise SystemExit(f"not ok - {description}\n{detail}")
  print(f"ok - {description}")


with tempfile.TemporaryDirectory(prefix="rpi-upgrade-guide-") as temporary:
  root = Path(temporary)
  checkout = root / "source"
  checkout.mkdir()
  stubs = root / "bin"
  stubs.mkdir()
  calls = root / "calls"
  profile = root / "profile"

  def git(*args):
    return subprocess.check_output([real_git, "-C", str(checkout), *args], text=True, stderr=subprocess.DEVNULL).strip()

  git("init", "-q", "-b", "main")
  git("-c", "user.name=Upgrade fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "initial", "--allow-empty")
  git("remote", "add", "origin", "https://github.com/pkyanam/omarchy-4-pi.git")
  git("update-ref", "refs/remotes/origin/main", "HEAD")
  git("branch", "--set-upstream-to=origin/main", "main")

  def stub(name, body):
    path = stubs / name
    path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
    path.chmod(0o755)

  stub("git", '''if [[ ${1:-} == "-C" ]]; then
  case ${3:-} in
    symbolic-ref|rev-parse|status) exec "$REAL_GIT" "$@" ;;
    remote)
      if [[ ${4:-} == "get-url" ]]; then exec "$REAL_GIT" "$@"; fi ;;
  esac
fi
echo "git $*" >>"$CALL_LOG"
exit 91
''')
  for name in ("sudo", "pacman", "pacman-key", "makepkg", "curl", "wget", "omarchy-update-pacman"):
    stub(name, 'echo "${0##*/} $*" >>"$CALL_LOG"; exit 91\n')
  for name in ("omarchy-hw-raspberry-pi", "omarchy-hw-aarch64"):
    stub(name, "exit 0\n")
  stub("pacman-conf", '''case "$*" in
  Architecture) echo aarch64 ;;
  --repo-list) printf 'omarchy\\ncore\\nextra\\nalarm\\n' ;;
  IgnorePkg) echo 'omarchy omarchy-settings omarchy-dev omarchy-settings-dev' ;;
  *)
    [[ $# == 3 && $1 == --repo ]] || exit 91
    case $3 in
      Server)
        if [[ $2 == omarchy ]]; then echo https://pkgs.omarchy.org/stable/aarch64
        else echo "https://arm-stable-mirror.omarchy.org/aarch64/$2"; fi ;;
      CacheServer) ;;
      SigLevel) echo 'Required DatabaseOptional' ;;
      *) exit 91 ;;
    esac ;;
esac
''')
  env = dict(os.environ, PATH=f"{stubs}:{repo / 'bin'}:{os.environ['PATH']}",
    OMARCHY_PATH=str(repo), OMARCHY_RPI4_PROFILE=str(profile),
    CALL_LOG=str(calls), REAL_GIT=real_git, OMARCHY_UPDATE_LOGGED="1")
  # A caller's inherited marker must not make a legacy profile look new.
  for name in ("OMARCHY_RPI4_PACKAGE_POLICY", "OMARCHY_PACMAN_PROFILE"):
    env.pop(name, None)

  def write_profile(stable):
    profile.write_text(f"OMARCHY_RPI4_SOURCE={shlex.quote(str(checkout))}\nOMARCHY_PACMAN_PROFILE=rpi4\n" +
      ("OMARCHY_RPI4_PACKAGE_POLICY=stable-4.5\n" if stable else ""))

  def run(*args):
    calls.write_text("")
    result = subprocess.run([bash, *args], env=env, text=True, capture_output=True)
    return result, calls.read_text()

  def refuse(description, *args, diagnostic):
    result, operations = run(*args)
    check(result.returncode != 0 and not operations and diagnostic in result.stderr,
      description, f"status={result.returncode}, operations={operations!r}\n{result.stdout}{result.stderr}")

  write_profile(False)
  refuse("legacy normal update refuses before source fetch or privileged operations",
    str(repo / "bin/omarchy-update"), "-y", diagnostic="legacy rolling ALARM profile")
  refuse("legacy source-only preparation also refuses before fetch",
    str(repo / "bin/omarchy-update-rpi4"), "--prepare", diagnostic="legacy rolling ALARM profile")
  # Exercise new installer leaves as an OLD updater would source them. Do not
  # fake ensure_package_sources/install_arm_packages: their real early guard
  # must stop before any clone, keyring bootstrap, package refresh or build.
  for leaf in ("ensure_package_sources", "install_arm_packages"):
    refuse(f"old updater sourcing {leaf} stops before recipe or package mutation",
      "-c", f'source "$OMARCHY_PATH/install-rpi4.sh"; {leaf}',
      diagnostic="Legacy rolling ALARM profile")

  write_profile(True)
  result, operations = run(str(repo / "bin/omarchy-update-rpi4-guard"))
  check(result.returncode == 0 and not operations,
    "clean reviewed main with the 4.5 profile passes the real guard", result.stderr)
  git("checkout", "-qb", "codex/omarchy-4.5-pi4")
  refuse("unpublished clean candidate refuses the normal update before fetch",
    str(repo / "bin/omarchy-update"), "-y", diagnostic="expected the Pi main branch")
  git("checkout", "-q", "main")
  (checkout / "preserved-user-change").write_text("keep this source edit\n")
  refuse("dirty main refuses the normal update without erasing the user's change",
    str(repo / "bin/omarchy-update"), "-y", diagnostic="source has local changes")
  check((checkout / "preserved-user-change").read_text() == "keep this source edit\n",
    "refusing an update preserves source changes")
