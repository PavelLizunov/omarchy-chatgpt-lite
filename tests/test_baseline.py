"""Safe local checks; lifecycle uses real GApplication with an inert panel."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from core import (arguments, application_id, bounded_width, private_directory,
                  profile_paths, read_config, reload_safe, safe_navigation, transition, write_config)


class CoreTests(unittest.TestCase):
    def test_transition_matrix(self):
        expected = {
            "STOPPED": {"show": "VISIBLE", "toggle": "VISIBLE", "hide": "STOPPED", "quit": "STOPPED"},
            "HIDDEN": {"show": "VISIBLE", "toggle": "VISIBLE", "hide": "HIDDEN", "quit": "STOPPED"},
            "VISIBLE": {"show": "VISIBLE", "toggle": "HIDDEN", "hide": "HIDDEN", "quit": "STOPPED"},
        }
        for state, commands in expected.items():
            for command, result in commands.items():
                with self.subTest(state=state, command=command):
                    self.assertEqual(transition(state, command), result)
        for command in ("reload", "lite-on", "lite-off", "status"):
            self.assertEqual(transition("STOPPED", command), "STOPPED")

    def test_reload_requires_positive_complete_evidence(self):
        report = {"draft": "EMPTY", "generation": "IDLE_CONTROL", "recognized_page": "CHAT_HOME"}
        self.assertTrue(reload_safe(report, "FINISHED", 0))
        for key in report:
            for value in (None, False, "UNKNOWN", "PRESENT", "ACTIVE"):
                self.assertFalse(reload_safe({**report, key: value}, "FINISHED", 0))
        self.assertFalse(reload_safe(report, "LOADING", 0))
        self.assertFalse(reload_safe(report, "FINISHED", 1))
        self.assertFalse(reload_safe(None, "FINISHED", 0))

    def test_xdg_paths_and_defaults(self):
        self.assertEqual(profile_paths({"HOME": "/tmp/home"})["data"],
                         Path("/tmp/home/.local/share/omarchy-chatgpt-lite"))
        self.assertEqual(profile_paths({"HOME": "/tmp/home", "XDG_DATA_HOME": "/tmp/data"})["data"],
                         Path("/tmp/data/omarchy-chatgpt-lite"))
        with self.assertRaises(ValueError):
            profile_paths({"HOME": "/tmp/home", "XDG_CACHE_HOME": "relative"})

    def test_private_profile_and_atomic_preference(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = profile_paths(test_root=folder)
            for path in paths.values():
                private_directory(path)
                self.assertEqual(path.stat().st_mode & 0o777, 0o700)
            self.assertEqual(read_config(paths)["width"], 620)
            write_config(paths, {"width": 800, "lite_requested": True})
            self.assertEqual(read_config(paths), {"width": 800, "lite_requested": True})
            target = paths["config"] / "settings.json"
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(paths["config"].iterdir()), [target])
            target.chmod(0o644)
            with self.assertRaises(ValueError):
                read_config(paths)

    def test_rejects_symlink_profile_and_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            real = root / "real"
            real.mkdir()
            linked = root / "linked"
            linked.symlink_to(real, target_is_directory=True)
            with self.assertRaises(OSError):
                private_directory(linked)
            paths = profile_paths(test_root=root / "profile")
            private_directory(paths["config"])
            external = root / "external.json"
            external.write_text('{}')
            (paths["config"] / "settings.json").symlink_to(external)
            with self.assertRaises(OSError):
                write_config(paths, {"width": 620, "lite_requested": False})
            self.assertEqual(external.read_text(), '{}')

    def test_rejects_invalid_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = profile_paths(test_root=folder)
            private_directory(paths["config"])
            target = paths["config"] / "settings.json"
            for value in ({"width": True}, {"width": 239}, {"lite_requested": "yes"}, {"other": 1}, []):
                target.write_text(json.dumps(value))
                target.chmod(0o600)
                with self.assertRaises(ValueError):
                    read_config(paths)
            target.write_bytes(b"x" * 8193)
            with self.assertRaises(ValueError):
                read_config(paths)

    def test_dimensions_and_uri_policy(self):
        self.assertEqual(bounded_width(620, 500), 500)
        self.assertEqual(bounded_width(620, 1920), 620)
        self.assertEqual(bounded_width(620, 180), 180)
        for uri in ("https://chatgpt.com", "https://accounts.google.com", "about:blank"):
            self.assertTrue(safe_navigation(uri))
        for uri in ("javascript:alert(1)", "file:///etc/passwd", "http://chatgpt.com", "https://user:pw@example.com"):
            self.assertFalse(safe_navigation(uri))
        self.assertFalse(safe_navigation("https://chatgpt.com", fixture=True))
        self.assertTrue(safe_navigation((ROOT / "fixtures/baseline.html").as_uri(), fixture=True))
        self.assertFalse(safe_navigation("file:///etc/passwd", fixture=True))
        self.assertFalse(safe_navigation("https://[invalid", fixture=True))

    def test_fixture_identity_and_parser(self):
        self.assertNotEqual(application_id("/tmp/one"), application_id("/tmp/two"))
        self.assertEqual(application_id("/tmp/one"), application_id("/tmp/one"))
        opts = arguments(["show", "--fixture", str(ROOT / "fixtures/baseline.html"),
                          "--profile-root", "/tmp/fixture-profile"])
        self.assertEqual(opts.command, "show")


class InstallerTests(unittest.TestCase):
    def test_destination_guard_and_candidate_contract(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("candidate_install", ROOT / "install.py")
        installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(installer)
        self.assertEqual(len(installer.candidate(ROOT)), 8)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "file"
            path.write_text("inert")
            installer.owned_path(path)
            linked = Path(folder) / "linked"
            linked.symlink_to(path)
            with self.assertRaises(ValueError):
                installer.owned_path(linked)
            parent = Path(folder) / "parent"
            parent.mkdir()
            ancestor = Path(folder) / "ancestor"
            ancestor.symlink_to(parent, target_is_directory=True)
            with self.assertRaises(ValueError):
                installer.owned_path(ancestor / "new" / "file")
            with self.assertRaises(ValueError):
                installer.owned_path(path, directory=True)
            hardlink = Path(folder) / "hardlink"
            os.link(path, hardlink)
            with self.assertRaises(ValueError):
                installer.owned_path(path)

    def test_installer_preserves_unknown_files_and_backup(self):
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location("isolated_install", ROOT / "install.py")
        installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(installer)
        calls = []
        def inert_run(*args):
            calls.append(args)
            if args[-1] == "status":
                return '{"state":"STOPPED"}'
            if "list" in args:
                return '[]'
            return ""
        with tempfile.TemporaryDirectory() as folder:
            env = {"HOME": folder, "XDG_CONFIG_HOME": folder + "/config", "XDG_DATA_HOME": folder + "/data"}
            with patch.dict(os.environ, env), patch.object(installer, "run", inert_run):
                installer.install()
                target = Path(folder) / "config/omarchy/plugins/slovn.chatgpt-lite"
                sentinel = target / "user-owned.txt"
                sentinel.write_text("preserve me")
                installer.install()
                self.assertEqual(sentinel.read_text(), "preserve me")
                backups = list((Path(folder) / "data/omarchy-chatgpt-lite-install-backups").glob("candidate-*"))
                self.assertEqual(len(backups), 1)
                self.assertEqual((backups[0] / "slovn.chatgpt-lite/user-owned.txt").read_text(), "preserve me")
                installed_app = target / "app.py"
                installed_app.write_text(installed_app.read_text() + "\n# Previous installed candidate\n")
                old_app = installed_app.read_bytes()
                os.link(target / "core.py", Path(folder) / "core-hardlink")
                with self.assertRaises(ValueError):
                    installer.install()
                self.assertEqual(installed_app.read_bytes(), old_app)
                (Path(folder) / "core-hardlink").unlink()
                launcher = Path(folder) / "data/applications/slovn.chatgpt_lite.desktop"
                launcher.write_text("Unrelated launcher")
                with self.assertRaises(ValueError):
                    installer.install()
                self.assertEqual(launcher.read_text(), "Unrelated launcher")
        self.assertTrue(any("enable" in call for call in calls))


class InertPanel:
    """No GTK, filesystem, page data or network; exercise actual IPC dispatch."""
    def __init__(self, app):
        self.app = app

    def show(self):
        self.app.load_status = "INERT_FIXTURE"

    def hide(self):
        pass

    def destroy(self):
        pass


class ApplicationTests(unittest.TestCase):
    def test_launcher_focus_transfer_does_not_dismiss_before_interaction(self):
        from app import Sidebar
        from types import SimpleNamespace
        from gi.repository import GLib
        panel = Sidebar.__new__(Sidebar)
        panel.app = SimpleNamespace(state="VISIBLE")
        panel.focus_seen = True
        panel.focus_armed = False
        panel.focus_timer = None
        inactive = SimpleNamespace(is_active=lambda: False)
        try:
            panel.focus_changed(inactive, None)
            self.assertIsNone(panel.focus_timer, "launcher focus transition must not dismiss a fresh panel")
            panel.focus_armed = True
            panel.focus_changed(inactive, None)
            self.assertIsNotNone(panel.focus_timer, "interaction enables outside-focus dismissal")
        finally:
            if panel.focus_timer is not None:
                GLib.source_remove(panel.focus_timer)

    def test_failed_show_destroys_candidate(self):
        from app import Application
        with tempfile.TemporaryDirectory() as folder:
            options = arguments(["show", "--fixture", str(ROOT / "fixtures/baseline.html"),
                                 "--profile-root", folder])
            destroyed = []

            class BrokenPanel(InertPanel):
                def show(self):
                    raise RuntimeError("inert activation failure")

                def destroy(self):
                    destroyed.append(True)

            app = Application(options, panel_factory=BrokenPanel)
            with self.assertRaises(RuntimeError):
                app.dispatch("show")
            self.assertEqual(destroyed, [True])
            self.assertIsNone(app.panel)
            self.assertEqual(app.state, "STOPPED")
            self.assertEqual(app.view_creations, 0)

    @unittest.skipUnless(os.environ.get("CHATGPT_LITE_TEST_BUS") == "1", "run inside the documented isolated D-Bus session")
    def test_real_single_instance_commands(self):
        from app import has_owner
        with tempfile.TemporaryDirectory() as folder:
            suffix = ["--fixture", str(ROOT / "fixtures/baseline.html"), "--profile-root", folder]
            worker = [sys.executable, str(Path(__file__)), "--worker"]
            app_id = application_id(folder)
            process = subprocess.Popen([*worker, "show", *suffix], stdout=subprocess.DEVNULL,
                                       stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while not has_owner(app_id):
                    if process.poll() is not None or time.monotonic() > deadline:
                        self.fail("inert GApplication did not register")
                    time.sleep(0.02)

                def call(command):
                    return subprocess.run([*worker, command, *suffix], capture_output=True,
                                          text=True, timeout=5)

                for index in range(10):
                    for command in ("show", "hide", "hide", "toggle", "show"):
                        result = call(command)
                        self.assertEqual(result.returncode, 0, result.stderr)
                    result = call("status")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    state = json.loads(result.stdout)
                    self.assertEqual(state["state"], "VISIBLE")
                    self.assertEqual(state["pid"], process.pid)
                    self.assertEqual(state["primary_views_created"], 1)
                self.assertEqual(call("reload").returncode, 2)
                self.assertEqual(call("lite-on").returncode, 0)
                self.assertEqual(json.loads(call("status").stdout)["reduction"], "DEGRADED")
                self.assertEqual(call("lite-off").returncode, 0)
                self.assertEqual(call("quit").returncode, 0)
                self.assertEqual(process.wait(timeout=5), 0)
                self.assertFalse(has_owner(app_id))
                # These execute the real CLI, with no injected inert panel needed.
                for command in ("hide", "quit", "reload", "lite-on", "lite-off", "status"):
                    result = subprocess.run([sys.executable, str(ROOT / "app.py"), command, *suffix],
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertFalse(has_owner(app_id))
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
                process.stderr.close()


if __name__ == "__main__":
    if "--worker" in sys.argv:
        from app import Application
        argv = sys.argv[sys.argv.index("--worker") + 1:]
        options = arguments(argv)
        app = Application(options, panel_factory=InertPanel)
        sys.exit(app.run([str(Path(__file__)), *argv]))
    unittest.main()
