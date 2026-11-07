"""Exercise the actual client without requiring a Bluetooth adapter or bus."""

import os
from pathlib import Path
import resource
import subprocess
import sys
import tempfile


def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="bluez-bus-check-", dir="/tmp") as temporary:
    environment = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=f"unix:path={temporary}/missing")
    # Keep libdbus argument checks fatal, including when the caller disabled them.
    environment.pop("DBUS_FATAL_WARNINGS", None)
    for command in ("list", "show", "devices"):
        result = subprocess.run([binary, command], env=environment, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=10, preexec_fn=no_core)
        if result.returncode != 1 or "Failed to connect to system D-Bus:" not in result.stderr:
            sys.exit(f"{command}: expected a connection error and exit 1; got "
                     f"{result.returncode}: {result.stderr}")
        print(f"ok - bluetoothctl {command} reports an unavailable bus and exits 1")
