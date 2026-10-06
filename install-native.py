#!/usr/bin/python -B
"""Install a native candidate; restore task-owned routing on activation failure."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
from install import owned_path, run

PLUGIN_ID = 'slovn.chatgpt-lite'
FILES = ('native/BarWidget.qml', 'native/Service.qml', 'native/Content.qml', 'native/Browser.qml', 'native/Theme.js', 'native/prepare-profile.py')


def manifest():
    result = json.loads((ROOT / 'manifest.json').read_text())
    result.update(version='0.4.0-dev', keepLoaded=True,
                  description='Original ChatGPT in a compact native top-bar popover.',
                  kinds=['service', 'bar-widget'],
                  entryPoints={'service': 'native/Service.qml', 'barWidget': 'native/BarWidget.qml'},
                  barWidget={'defaultSection': 'right', 'displayName': 'ChatGPT Lite',
                             'description': 'Toggle the original ChatGPT popover',
                             'category': 'Apps', 'allowMultiple': False})
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def activate():
    run('omarchy-shell', 'shell', 'rescanPlugins')
    run('omarchy', 'plugin', 'enable', PLUGIN_ID)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        try:
            status = json.loads(run('omarchy-shell', PLUGIN_ID, 'status'))
            if status.get('engine') == 'QTWEBENGINE' and status.get('state') == 'STOPPED':
                if status.get('host_compatible') is not True:
                    raise ValueError('Host discarded application arguments')
                return
        except (json.JSONDecodeError, subprocess.SubprocessError):
            pass
        time.sleep(0.2)
    raise ValueError('Native entry IPC did not recover')


def publish(stage, target, backup, activate_candidate=activate, command=run):
    """Rollback only replaced code, never unknown files or browser profiles."""
    names = (*FILES, 'manifest.json')
    previous = {name: digest(target / name) for name in names}
    published = {}
    try:
        for name in names:
            out = target / name
            owned_path(out)
            owned_path(out.parent, directory=True)
            if digest(out) != previous[name]:
                raise ValueError('Installed code changed concurrently')
            out.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            expected = digest(stage / name)
            os.replace(stage / name, out)
            published[name] = expected
            if digest(out) != expected:
                raise ValueError('Installed source mismatch')
        activate_candidate()
    except (ValueError, OSError, subprocess.SubprocessError) as cause:
        # Fail closed if disable or concurrency checks fail; do not overwrite
        # someone else's concurrent work while trying to recover our own files.
        command('omarchy', 'plugin', 'disable', PLUGIN_ID)
        for name, expected in published.items():
            if digest(target / name) != expected:
                raise ValueError('Rollback blocked by concurrent code change; backup: ' + str(backup)) from cause
        for name in published:
            out = target / name
            old = backup / PLUGIN_ID / name
            if previous[name] is None:
                out.unlink()
            else:
                if digest(old) != previous[name]:
                    raise ValueError('Recovery copy changed; backup: ' + str(backup)) from cause
                owned_path(out)
                with tempfile.NamedTemporaryFile(dir=out.parent, delete=False) as handle:
                    temporary = Path(handle.name)
                try:
                    shutil.copy2(old, temporary)
                    os.replace(temporary, out)
                finally:
                    temporary.unlink(missing_ok=True)
        command('omarchy-shell', 'shell', 'rescanPlugins')
        # Entry was disabled on arrival; preserve that state after rollback.
        raise ValueError('Native install rolled back, plugin disabled; backup: ' + str(backup)) from cause


def native_install():
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    data = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
    if not config.is_absolute() or not data.is_absolute():
        raise ValueError('XDG paths must be absolute')
    plugins = config / 'omarchy/plugins'
    target = plugins / PLUGIN_ID
    before = {name: digest(ROOT / name) for name in FILES}
    for name in FILES:
        if before[name] is None or any(p.is_symlink() for p in (ROOT / name, *(ROOT / name).parents)):
            raise ValueError('Expected ordinary candidate files without symlinks')
    status = json.loads(run('/usr/bin/python', '-B', str(ROOT / 'app.py'), 'status'))
    if status['state'] != 'STOPPED':
        raise ValueError('Stop the legacy application before installing the native candidate')
    entries = json.loads(run('omarchy', 'plugin', 'list', '--json'))
    if any(p.get('id') == PLUGIN_ID and p.get('enabled') for p in entries):
        raise ValueError('Disable only this plugin before installation')
    for parent in (config, config / 'omarchy', plugins, target):
        owned_path(parent, directory=True)
    if not target.is_dir() or any(p.is_symlink() for p in target.rglob('*')):
        raise ValueError('Expected an ordinary installed plugin without symlinks')
    for name in (*FILES, 'manifest.json'):
        owned_path(target / name)
        owned_path((target / name).parent, directory=True)
    backup_root = data / 'omarchy-chatgpt-lite-install-backups'
    owned_path(backup_root, directory=True)
    backup_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='native-', dir=backup_root))
    shutil.copytree(target, backup / PLUGIN_ID)
    old_manifest = (target / 'manifest.json').read_bytes()
    with tempfile.TemporaryDirectory(prefix='.chatgpt-native-', dir=plugins) as folder:
        stage = Path(folder)
        for name in FILES:
            out = stage / name
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, out)
        (stage / 'manifest.json').write_text(json.dumps(manifest(), indent=2) + '\n')
        run('omarchy', 'plugin', 'validate', str(stage))
        if any(digest(ROOT / name) != value for name, value in before.items()):
            raise ValueError('Source changed during staging')
        if (target / 'manifest.json').read_bytes() != old_manifest:
            raise ValueError('Installed manifest changed concurrently')
        publish(stage, target, backup)
    print('Native entry loaded, browser not started. Backup:', backup)


if __name__ == '__main__':
    try:
        native_install()
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        print('Native installation refused or incomplete:', str(error), file=sys.stderr)
        sys.exit(1)
