#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
bash -n "$ROOT/bin/omarchy-pi-display"
python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time

script = str(Path(sys.argv[1]) / 'bin/omarchy-pi-display')
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    mock = root / 'hyprctl'
    mock.write_text('''#!/bin/bash
set -eu
echo "$*" >>"$FIXTURE/calls"
if [[ ${1:-} == -i ]]; then shift 2; fi
case "$*" in
  '-j instances') echo '[{}]' ;;
  '-j monitors'|'-j monitors all')
    if [[ -f $FIXTURE/preview && ${REJECT_MODE:-0} == 0 ]]; then w=1920; h=1200; else w=1024; h=768; fi
    echo "[{\\"name\\":\\"HDMI-A-1\\",\\"width\\":$w,\\"height\\":$h,\\"refreshRate\\":60,\\"scale\\":1,\\"x\\":0,\\"y\\":0}]"
    ;;
  eval*) touch "$FIXTURE/preview" ;;
  reload|configerrors) : ;;
  *) exit 1 ;;
esac
''')
    mock.chmod(0o755)
    env = dict(os.environ, PATH=tmp + ':' + os.environ['PATH'], FIXTURE=tmp,
               XDG_STATE_HOME=tmp + '/state')
    env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    profile = root / 'state/omarchy/toggles/hypr/pi-display-HDMI-A-1.lua'
    def run_preview(answer, reject=False):
        (root / 'preview').unlink(missing_ok=True)
        master, slave = pty.openpty()
        process = subprocess.Popen([script, 'nec-ea243wm'], stdin=slave, stdout=slave,
                                   stderr=slave, env=dict(env, REJECT_MODE=str(int(reject))))
        os.close(slave)
        output = b''
        sent = False
        deadline = time.monotonic() + 40
        try:
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        output += os.read(master, 8192)
                    except OSError:
                        break
                if b'Type yes' in output and not sent and answer is not None:
                    os.write(master, (answer + '\n').encode())
                    sent = True
            code = process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
        return code, output.decode(errors='replace')
    code, output = run_preview('no')
    assert code == 0, output
    assert not profile.exists()
    assert 'mode="1024x768@60"' in (root / 'calls').read_text()
    code, output = run_preview(None)
    assert code == 0 and not profile.exists(), output
    code, output = run_preview('yes', reject=True)
    assert code != 0 and not profile.exists(), output
    code, output = run_preview('yes')
    assert code == 0 and profile.exists(), output
    assert 'modeline 154.00 1920 1968 2000 2080' in profile.read_text()
    assert profile.stat().st_mode & 0o777 == 0o600
    code, output = run_preview('no')
    assert code == 0 and profile.exists(), output
    assert 'modeline 154.00' in (root / 'calls').read_text().splitlines()[-1]
    subprocess.run([script, 'reset'], env=env, check=True, capture_output=True)
    assert not profile.exists() and list(profile.parent.glob('*.disabled-*'))
    bad = subprocess.run([script, 'nec-ea243wm', 'HDMI-A-1";bad'], env=env, capture_output=True)
    assert bad.returncode == 64
    noninteractive = subprocess.run([script, 'nec-ea243wm'], env=env, stdin=subprocess.DEVNULL, capture_output=True)
    assert noninteractive.returncode != 0
print('ok - Pi display preview confirms, reverts, rejects failed modes, saves privately, and resets with backup')
PY
