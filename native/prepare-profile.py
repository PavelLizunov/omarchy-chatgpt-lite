#!/usr/bin/python
"""Prepare only native-engine directories without touching legacy WebKit storage."""
import os
from pathlib import Path
import stat


def prepare(base, child):
    if not base.is_absolute():
        raise ValueError('XDG root must be absolute')
    if any(p.is_symlink() for p in (base, *base.parents)):
        raise ValueError('Symlink profile ancestor forbidden')
    base.mkdir(parents=True, exist_ok=True)
    root = base / 'omarchy-chatgpt-lite-qt'
    root.mkdir(mode=0o700, exist_ok=True)
    for path in (root, root / child):
        path.mkdir(mode=0o700, exist_ok=True)
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            info = os.fstat(fd)
            if info.st_uid != os.getuid() or not stat.S_ISDIR(info.st_mode):
                raise ValueError('Profile must be owner-controlled directory')
            os.fchmod(fd, 0o700)
        finally:
            os.close(fd)


if __name__ == '__main__':
    # No persistent environment setting, privileged writes, credentials or logs.
    prepare(Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share'), 'profile')
    prepare(Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache'), 'cache')
