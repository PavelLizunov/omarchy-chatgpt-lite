#!/usr/bin/python -B
"""Start one managed patched host; fall back to stock on dependency drift."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
UNIT = 'omarchy-chatgpt-native-host.service'
ROOT = Path.home() / '.local/share/omarchy-chatgpt-lite-host'
PACKAGES = ('quickshell', 'qt6-base', 'qt6-declarative', 'qt6-wayland', 'qt6-webengine')


def compatible():
    try:
        expected = json.loads((ROOT / 'identity.json').read_text())
        packages = subprocess.check_output(['pacman', '-Q', *PACKAGES], text=True, timeout=5)
        def digest(path):
            return hashlib.sha256(path.read_bytes()).hexdigest()
        return (packages == expected['packages'] and digest(Path('/usr/bin/quickshell')) == expected['stock_sha256']
                and digest(ROOT / 'bin/quickshell') == expected['patched_sha256'])
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        return False


if __name__ == '__main__':
    if sys.argv[1:] == ['--guard']:
        sys.exit(0 if compatible() else 1)
    if not compatible():
        print('Native host dependency drift: using stock shell; native browser open will refuse unsupported host.', file=sys.stderr)
        os.execv('/usr/share/omarchy/bin/omarchy-launch-shell', ['omarchy-launch-shell'])
    # Refuse to overlap an existing config owner; IPC matching uses the same
    # path/display as the existing native Omarchy wrapper.
    probe = subprocess.run(['omarchy-shell', 'shell', 'ping'], capture_output=True, timeout=7)
    if probe.returncode == 0:
        sys.exit(0)
    try:
        subprocess.run(['systemctl', '--user', 'start', UNIT], check=True, timeout=15)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            probe = subprocess.run(['omarchy-shell', 'shell', 'ping'], capture_output=True, timeout=7)
            if probe.returncode == 0:
                sys.exit(0)
            time.sleep(0.2)
        raise RuntimeError('Native shell IPC did not recover')
    except (OSError, RuntimeError, subprocess.SubprocessError):
        # Supported service stop must finish before stock fallback: never run
        # two owners to conceal a failed launch.
        subprocess.run(['systemctl', '--user', 'stop', UNIT], check=True, timeout=15)
        os.execv('/usr/share/omarchy/bin/omarchy-launch-shell', ['omarchy-launch-shell'])
