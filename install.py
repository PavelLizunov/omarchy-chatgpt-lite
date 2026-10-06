#!/usr/bin/python -B
"""Install an independent stopped candidate; never delete profiles or user files."""

import hashlib
import json
import os
from pathlib import Path
import stat
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
PLUGIN_ID = "slovn.chatgpt-lite"
FILES = ("app.py", "core.py", "hostpipe.py", "Panel.qml", "manifest.json",
         "reduction/adapter.js", "reduction/diagnostics.js", "reduction/verification.json")
DESKTOP = "slovn.chatgpt_lite.desktop"


def candidate(root):
    if root.is_symlink() or any(p.is_symlink() for p in root.rglob("*")):
        raise ValueError("candidate symlinks forbidden")
    manifest = json.loads((root / "manifest.json").read_text())
    if (manifest.get("id") != PLUGIN_ID or manifest.get("schemaVersion") != 1
            or manifest.get("kinds") != ["panel"]
            or manifest.get("entryPoints") != {"panel": "Panel.qml"}):
        raise ValueError("unexpected manifest contract")
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in FILES}


def owned_path(path, directory=False):
    if any(component.is_symlink() for component in (path, *path.parents)):
        raise ValueError("symlink destination or ancestor forbidden")
    if path.exists():
        info = path.stat()
        expected = stat.S_ISDIR if directory else stat.S_ISREG
        if info.st_uid != os.getuid() or not expected(info.st_mode):
            raise ValueError("destination must be owner-controlled")
        if not directory and info.st_nlink != 1:
            raise ValueError("hardlinked destination forbidden")


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=10).stdout


def install():
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    data = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    if not config.is_absolute() or not data.is_absolute():
        raise ValueError("XDG paths must be absolute")
    plugins = config / "omarchy/plugins"
    target = plugins / PLUGIN_ID
    if target == ROOT:
        raise ValueError("run the installer from the source checkout")
    before = candidate(ROOT)
    run("omarchy", "plugin", "validate", str(ROOT))
    status = json.loads(run("/usr/bin/python", "-B", str(ROOT / "app.py"), "status"))
    if status["state"] != "STOPPED":
        raise ValueError("application running; preserve work and stop it before installation")
    entries = json.loads(run("omarchy", "plugin", "list", "--json"))
    if any(p.get("id") == PLUGIN_ID and p.get("enabled") for p in entries):
        raise ValueError("disable only this plugin before replacing its installed code")
    launcher = data / "applications" / DESKTOP
    if launcher.exists():
        if launcher.is_symlink() or "X-Omarchy-Plugin=slovn.chatgpt-lite\n" not in launcher.read_text():
            raise ValueError("unrelated launcher exists; not overwritten")
    for parent in (config, config / "omarchy", plugins, data, data / "applications"):
        owned_path(parent, directory=True)
    owned_path(launcher)
    launcher_before = launcher.read_bytes() if launcher.exists() else None
    plugins.mkdir(parents=True, exist_ok=True)
    backup = None
    old_hashes = None
    if target.exists() or target.is_symlink():
        if target.is_symlink() or not target.is_dir():
            raise ValueError("installed target must be an ordinary directory")
        old_hashes = candidate(target)
        backups = data / "omarchy-chatgpt-lite-install-backups"
        owned_path(backups, directory=True)
        backups.mkdir(mode=0o700, parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix="candidate-", dir=backups))
        shutil.copytree(target, backup / PLUGIN_ID)
        if launcher.exists():
            shutil.copy2(launcher, backup / DESKTOP)
    with tempfile.TemporaryDirectory(prefix=".chatgpt-lite-", dir=plugins) as folder:
        stage = Path(folder)
        for name in FILES:
            out = stage / name
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, out)
        if candidate(stage) != before or candidate(ROOT) != before:
            raise ValueError("source changed during staging")
        run("omarchy", "plugin", "validate", str(stage))
        if old_hashes is not None and candidate(target) != old_hashes:
            raise ValueError("installed candidate changed concurrently")
        # Validate every destination before replacing the first code file.
        owned_path(target, directory=True)
        for name in FILES:
            owned_path(target / name)
            owned_path((target / name).parent, directory=True)
        target.mkdir(mode=0o700, exist_ok=True)
        # Only known code files replaced; unknown files/data are retained.
        for name in FILES:
            out = target / name
            owned_path(out)
            owned_path(out.parent, directory=True)
            out.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage / name, out)
    if candidate(target) != before:
        raise ValueError("installed verification mismatch")
    launcher.parent.mkdir(parents=True, exist_ok=True)
    legacy = launcher.parent / "slovn.chatgpt-lite.desktop"
    if legacy.exists():
        owned_path(legacy)
        if "X-Omarchy-Plugin=slovn.chatgpt-lite\n" in legacy.read_text():
            if backup:
                shutil.copy2(legacy, backup / legacy.name)
            legacy.unlink()
    launcher_text = """[Desktop Entry]
Type=Application
Name=ChatGPT Lite
Comment=Toggle the original ChatGPT sidebar
Exec=omarchy-shell shell toggle slovn.chatgpt-lite {}
Icon=applications-internet
Terminal=false
Categories=Network;Chat;
StartupNotify=false
X-Omarchy-Plugin=slovn.chatgpt-lite
"""
    with tempfile.NamedTemporaryFile(mode="w", dir=launcher.parent, suffix=".desktop", delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(launcher_text)
    try:
        run("desktop-file-validate", str(temporary))
        owned_path(launcher)
        if (launcher.read_bytes() if launcher.exists() else None) != launcher_before:
            raise ValueError("launcher changed concurrently")
        temporary.chmod(0o644)
        os.replace(temporary, launcher)
    finally:
        temporary.unlink(missing_ok=True)
    run("omarchy-shell", "shell", "rescanPlugins")
    run("omarchy", "plugin", "enable", PLUGIN_ID)
    # Discovery/config reload is asynchronous. Wait boundedly without opening
    # any panel or restarting the shared shell.
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        try:
            run("omarchy-shell", "shell", "hide", PLUGIN_ID)
            break
        except subprocess.SubprocessError:
            time.sleep(0.2)
    else:
        raise ValueError("enabled candidate did not recover shell IPC within 8 seconds")
    print("Installed and enabled; browser stays stopped until summoned.")
    print("Launcher:", launcher)
    if backup:
        print("Restorable previous code/launcher:", backup)
    print("Profile untouched. Source hashes:", json.dumps(before, sort_keys=True))


if __name__ == "__main__":
    try:
        install()
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        print("Installation refused or incomplete:", str(error), file=sys.stderr)
        sys.exit(1)
