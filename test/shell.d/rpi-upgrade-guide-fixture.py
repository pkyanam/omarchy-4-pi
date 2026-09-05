"""Execute the documented bootstrap with fake Git/updater, never a live Pi."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

guide = (Path(os.environ["ROOT"]) / "docs/pi-upgrade.md").read_text()
command = re.search(r"```bash\n(bash -c .*?)\n```", guide, re.S).group(1)
with tempfile.TemporaryDirectory() as temporary:
  root = Path(temporary)
  checkout = root / "checkout"
  (checkout / ".git").mkdir(parents=True)
  (checkout / "bin").mkdir()
  fake_bin = root / "bin"
  fake_bin.mkdir()
  git = fake_bin / "git"
  git.write_text('''#!/bin/bash
set -euo pipefail
shift 2
case "$*" in
  "remote get-url origin") echo "${TEST_ORIGIN:-https://github.com/pkyanam/omarchy-4-pi.git}" ;;
  "symbolic-ref --quiet --short HEAD") echo "${TEST_BRANCH:-main}" ;;
  "rev-parse --abbrev-ref --symbolic-full-name @{upstream}") echo "${TEST_UPSTREAM:-origin/main}" ;;
  "status --porcelain") printf %s "${TEST_DIRTY:-}" ;;
  fetch*) echo fetch >>"$CALL_LOG"; exit "${TEST_FETCH_STATUS:-0}" ;;
  merge*) echo merge >>"$CALL_LOG"; exit "${TEST_MERGE_STATUS:-0}" ;;
  *) exit 90 ;;
esac
''')
  git.chmod(0o755)
  updater = checkout / "bin/omarchy-update"
  updater.write_text('''#!/bin/bash
[[ $CARGO_BUILD_JOBS == 2 && $CMAKE_BUILD_PARALLEL_LEVEL == 2 && $MAKEFLAGS == -j2 ]] || exit 91
echo update >>"$CALL_LOG"
exit "${TEST_UPDATE_STATUS:-0}"
''')
  updater.chmod(0o755)
  command = command.replace("checkout=/opt/omarchy-4-pi", f"checkout={checkout}")
  env = dict(os.environ, PATH=f"{fake_bin}:/usr/bin:/bin", CALL_LOG=str(root / "calls"))
  for name in ("MAKEFLAGS", "CARGO_BUILD_JOBS", "CMAKE_BUILD_PARALLEL_LEVEL"):
    env.pop(name, None)
  cases = [{}, {"TEST_ORIGIN": "https://github.com/omacom/omarchy.git"},
    {"TEST_BRANCH": "dev"}, {"TEST_UPSTREAM": "upstream/main"},
    {"TEST_DIRTY": " M local"}, {"TEST_FETCH_STATUS": "1"},
    {"TEST_MERGE_STATUS": "1"}, {"TEST_UPDATE_STATUS": "1"}]
  for case in cases:
    log = root / "calls"
    log.unlink(missing_ok=True)
    result = subprocess.run(["bash", "-c", command], env=env | case, text=True, capture_output=True)
    calls = log.read_text().splitlines() if log.exists() else []
    if not case:
      assert result.returncode == 0 and calls == ["fetch", "merge", "update"], (result, calls)
    else:
      assert result.returncode != 0, case
      if "TEST_UPDATE_STATUS" not in case:
        assert "update" not in calls, case
      if any(k in case for k in ("TEST_ORIGIN", "TEST_BRANCH", "TEST_UPSTREAM", "TEST_DIRTY")):
        assert not calls, case
  print(f"PASS: {len(cases)} documented bootstrap preflight/handoff cases")
