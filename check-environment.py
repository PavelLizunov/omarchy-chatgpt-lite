#!/usr/bin/python
"""Check required GI imports without initializing GTK or creating profile data."""

import importlib
import sys


def main():
    print(f"Interpreter: {sys.executable}")
    print(f"Python: {sys.version.split()[0]}")
    try:
        import gi
    except ImportError:
        print("FAILED: PyGObject unavailable; use /usr/bin/python.")
        return 1

    print(f"PyGObject: {gi.__version__}")
    failed = False
    for namespace, version in (
        ("Gtk", "4.0"),
        ("Gtk4LayerShell", "1.0"),
        ("WebKit", "6.0"),
    ):
        try:
            gi.require_version(namespace, version)
            module = importlib.import_module(f"gi.repository.{namespace}")
            actual = ".".join(
                str(getattr(module, f"get_{part}_version")())
                for part in ("major", "minor", "micro")
            )
            print(f"AVAILABLE: {namespace} {version}; library {actual}")
        except (ValueError, ImportError, AttributeError) as exc:
            print(f"FAILED: {namespace} {version}: {exc}")
            failed = True
    print("ChatGPT, layer-shell placement and plugin lifecycle: NOT_VERIFIED")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
