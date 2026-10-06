"""Profile safety, command validation and lifecycle rules; no GUI or network I/O."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
from urllib.parse import unquote, urlsplit

NAME = "omarchy-chatgpt-lite"
APP_ID = "dev.slovn.ChatGPTLite"
COMMANDS = ("show", "hide", "toggle", "quit", "reload", "lite-on", "lite-off", "status", "diagnostics")
MAX_CONFIG_BYTES = 8192


def arguments(argv):
    parser = argparse.ArgumentParser(description="Original ChatGPT in a persistent GTK4 sidebar")
    parser.add_argument("command", nargs="?", choices=COMMANDS, default="show")
    parser.add_argument("--host-pipe", action="store_true", help="Owned plugin stdin/stdout lifecycle channel")
    parser.add_argument("--fixture", type=Path, help="Local test HTML under this project's fixtures/")
    parser.add_argument("--profile-root", type=Path, help="Isolated test profile; requires --fixture")
    args = parser.parse_args(argv)
    if bool(args.fixture) != bool(args.profile_root):
        parser.error("--fixture and --profile-root must be used together")
    if args.fixture:
        fixture_root = Path(__file__).parent.resolve() / "fixtures"
        args.fixture = args.fixture.resolve(strict=True)
        if not args.fixture.is_relative_to(fixture_root) or args.fixture.suffix != ".html":
            parser.error("fixture must be an HTML file under this project's fixtures/")
        if not args.profile_root.is_absolute():
            parser.error("--profile-root must be absolute")
    return args


def profile_paths(env=None, test_root=None):
    if test_root is not None:
        root = Path(test_root)
        if not root.is_absolute():
            raise ValueError("test profile root must be absolute")
        return {key: root / key for key in ("data", "cache", "config", "state")}
    env = os.environ if env is None else env
    home = Path(env.get("HOME", str(Path.home())))
    defaults = {"data": home / ".local/share", "cache": home / ".cache",
                "config": home / ".config", "state": home / ".local/state"}
    result = {}
    for key, default in defaults.items():
        base = Path(env.get(f"XDG_{key.upper()}_HOME") or default)
        if not base.is_absolute():
            raise ValueError("XDG paths must be absolute")
        result[key] = base / NAME
    return result


def private_directory(path):
    """Do not follow a symlink for an application-owned directory."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.getuid():
            raise ValueError("profile directory must be owned by the current user")
        os.fchmod(fd, 0o700)
    finally:
        os.close(fd)


def read_config(paths):
    path = paths["config"] / "settings.json"
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return {"width": 620, "lite_requested": False}
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise ValueError("settings must be an owner-controlled regular file")
        if info.st_mode & 0o077:
            raise ValueError("settings permissions must be owner-only")
        raw = handle.read(MAX_CONFIG_BYTES + 1)
    if len(raw) > MAX_CONFIG_BYTES:
        raise ValueError("settings exceed size limit")
    config = json.loads(raw)
    if not isinstance(config, dict) or set(config) - {"width", "lite_requested"}:
        raise ValueError("unsupported settings")
    width = config.get("width", 620)
    lite = config.get("lite_requested", False)
    if type(width) is not int or not 240 <= width <= 4096 or type(lite) is not bool:
        raise ValueError("invalid settings values")
    return {"width": width, "lite_requested": lite}


def write_config(paths, config):
    private_directory(paths["config"])
    target = paths["config"] / "settings.json"
    # Validate an existing target before atomically replacing it.
    read_config(paths)
    with tempfile.NamedTemporaryFile(mode="w", dir=paths["config"], delete=False) as handle:
        temporary = Path(handle.name)
        try:
            json.dump(config, handle)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        except BaseException:
            temporary.unlink()
            raise
    try:
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def application_id(test_root=None):
    if test_root is None:
        return APP_ID
    token = hashlib.sha256(str(Path(test_root).resolve()).encode()).hexdigest()[:24]
    return f"{APP_ID}.Fixture.p{token}"


def transition(state, command):
    if state not in ("STOPPED", "HIDDEN", "VISIBLE") or command not in COMMANDS:
        raise ValueError("unknown state or command")
    if command == "quit":
        return "STOPPED"
    if command == "show":
        return "VISIBLE"
    if command == "hide":
        return "HIDDEN" if state != "STOPPED" else "STOPPED"
    if command == "toggle":
        return "HIDDEN" if state == "VISIBLE" else "VISIBLE"
    return state


def reload_safe(report, load_status, auxiliary_count):
    """Unknown evidence never authorizes discarding a live page."""
    return (isinstance(report, dict) and load_status == "FINISHED"
            and auxiliary_count == 0 and report.get("draft") == "EMPTY"
            and report.get("generation") == "IDLE_CONTROL"
            and report.get("recognized_page") in {"CHAT_HOME", "CONVERSATION"})


def bounded_width(requested, available):
    if type(requested) is not int or type(available) is not int or available <= 0:
        raise ValueError("invalid panel dimensions")
    return min(max(240, requested), available)


def safe_navigation(uri, fixture=False):
    """Only normal HTTPS navigation in production; no external protocol launch."""
    try:
        parsed = urlsplit(uri)
        if parsed.scheme == "https":
            return not fixture and bool(parsed.hostname) and not parsed.username and not parsed.password
        if fixture and parsed.scheme == "file" and not parsed.netloc:
            root = Path(__file__).parent.resolve() / "fixtures"
            path = Path(unquote(parsed.path)).resolve()
            return path.is_relative_to(root) and path.suffix == ".html" and path.is_file()
        return uri == "about:blank"
    except (ValueError, OSError):
        return False
