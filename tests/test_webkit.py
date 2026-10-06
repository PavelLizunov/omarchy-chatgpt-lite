"""Actual consumer checks require WebKitGTK and an explicitly isolated Broadway display."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import subprocess
import select
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def webkit_available():
    if importlib.util.find_spec("gi") is None:
        return False
    import gi
    try:
        gi.require_version("WebKit", "6.0")
        return True
    except ValueError:
        return False


@unittest.skipUnless(
    webkit_available() and os.environ.get("CHATGPT_LITE_TEST_WEBKIT") == "1"
    and os.environ.get("GDK_BACKEND") == "broadway"
    and bool(os.environ.get("BROADWAY_DISPLAY")),
    "requires WebKit 6.0 and an explicitly authorized isolated Broadway test display",
)
class WebKitTests(unittest.TestCase):
    def test_actual_view_retains_draft_and_related_popup(self):
        from app import Application, Sidebar
        from core import arguments
        from gi.repository import GLib
        with tempfile.TemporaryDirectory() as folder:
            opts = arguments(["show", "--fixture", str(ROOT / "fixtures/baseline.html"),
                              "--profile-root", folder])
            app = Application(opts)
            panel = Sidebar(app)
            app.panel = panel
            try:
                panel.show()
                app.state = "VISIBLE"
                context = GLib.MainContext.default()

                def wait(predicate):
                    deadline = time.monotonic() + 10
                    while not predicate():
                        if time.monotonic() > deadline:
                            self.fail("local WebKit check timed out")
                        if context.pending():
                            context.iteration(False)
                        else:
                            time.sleep(0.01)

                def evaluate(script):
                    result = []
                    errors = []

                    def finished(view, async_result, _data):
                        try:
                            result.append(view.evaluate_javascript_finish(async_result).to_json(0))
                        except GLib.Error:
                            errors.append(True)

                    panel.view.evaluate_javascript(script, -1, None, None, None, finished, None)
                    wait(lambda: result or errors)
                    self.assertFalse(errors)
                    return json.loads(result[0])

                wait(lambda: app.load_status == "FINISHED")
                self.assertFalse(panel.session.is_ephemeral())
                self.assertTrue(evaluate("Boolean(document.querySelector('#draft'))"))
                evaluate("document.querySelector('#draft').value = 'Local unsent draft'")
                primary = panel.view
                for _ in range(10):
                    panel.hide()
                    app.state = "HIDDEN"
                    panel.show()
                    app.state = "VISIBLE"
                self.assertIs(panel.view, primary)
                # Real GTK controller callback, asynchronous WebKit overlay guard.
                from gi.repository import Gdk
                evaluate("var overlay=document.createElement('div'); overlay.setAttribute('role','dialog'); overlay.textContent='Local menu'; document.body.append(overlay); true")
                panel.key_pressed(panel.keys, Gdk.KEY_Escape, 0, 0)
                overlay_reports = []
                panel.diagnostics_report(overlay_reports.append)
                wait(lambda: bool(overlay_reports))
                self.assertEqual(app.state, "VISIBLE")
                evaluate("overlay.remove(); true")
                panel.key_pressed(panel.keys, Gdk.KEY_Escape, 0, 0)
                wait(lambda: app.state == "HIDDEN")
                self.assertEqual(evaluate("document.querySelector('#draft').value"), "Local unsent draft")
                panel.show()
                app.state = "VISIBLE"
                self.assertFalse(panel.key_pressed(panel.keys, Gdk.KEY_Escape, 0, Gdk.ModifierType.SHIFT_MASK))
                self.assertEqual(evaluate("document.querySelector('#draft').value"), "Local unsent draft")
                snapshot_path = os.environ.get("CHATGPT_LITE_SNAPSHOT")
                if snapshot_path:
                    from gi.repository import WebKit
                    snapshot_done = []

                    def snapshot_ready(view, result, _data):
                        texture = view.get_snapshot_finish(result)
                        self.assertTrue(texture.save_to_png(snapshot_path))
                        print(f"LOCAL_FIXTURE_SNAPSHOT {texture.get_width()}x{texture.get_height()} {snapshot_path}")
                        snapshot_done.append(True)

                    panel.view.get_snapshot(WebKit.SnapshotRegion.VISIBLE, WebKit.SnapshotOptions.NONE,
                                            None, snapshot_ready, None)
                    wait(lambda: bool(snapshot_done))
                evaluate("document.querySelector('#popup').click(); true")
                wait(lambda: bool(panel.child_ready))
                self.assertEqual(len(panel.children), 1)
                child_window = panel.children[0]
                # Exercise actual GTK focus group, without compositor/desktop I/O.
                from gi.repository import Gtk
                panel.focus_seen = True
                panel.interacted(panel.clicks)
                panel.focus_changed(child_window, None)
                self.assertIsNotNone(panel.focus_timer)
                outsider = Gtk.Window(title="Inert outside focus")
                outsider.present()
                outsider_reports = []
                panel.diagnostics_report(outsider_reports.append)
                wait(lambda: bool(outsider_reports))
                panel.dismiss_unfocused()
                self.assertEqual(app.state, "HIDDEN")
                outsider.destroy()
                panel.show()
                app.state = "VISIBLE"
                child = panel.children[0].get_child()
                self.assertEqual(child.get_network_session(), panel.session)
                self.assertFalse(panel.key_pressed(panel.keys, Gdk.KEY_Escape, 0, 0))
                panel.child_close(panel.children[0])
                self.assertEqual(panel.children, [])
            finally:
                panel.destroy()
                app.panel = None

    def test_actual_cli_single_view_and_shutdown(self):
        from app import has_owner
        from core import application_id
        with tempfile.TemporaryDirectory() as folder:
            suffix = ["--fixture", str(ROOT / "fixtures/baseline.html"), "--profile-root", folder]
            command = [sys.executable, str(ROOT / "app.py")]
            with tempfile.TemporaryFile() as log:
                process = subprocess.Popen([*command, "show", *suffix], stdout=log, stderr=log)
                try:
                    deadline = time.monotonic() + 15

                    def call(action):
                        return subprocess.run([*command, action, *suffix], capture_output=True,
                                              text=True, timeout=5)

                    while True:
                        if process.poll() is not None or time.monotonic() > deadline:
                            log.seek(0)
                            self.fail("actual CLI did not become ready: " + log.read().decode(errors="replace"))
                        if has_owner(application_id(folder)):
                            result = call("status")
                            if result.returncode == 0 and json.loads(result.stdout)["load_status"] == "FINISHED":
                                break
                        time.sleep(0.02)
                    diagnostic = json.loads(call("diagnostics").stdout)
                    self.assertEqual(diagnostic["schema"], 1)
                    self.assertEqual(diagnostic["draft"], "PRESENT")
                    for _ in range(10):
                        for action in ("hide", "show", "show"):
                            result = call(action)
                            self.assertEqual(result.returncode, 0, result.stderr)
                        state = json.loads(call("status").stdout)
                        self.assertEqual(state["pid"], process.pid)
                        self.assertEqual(state["primary_views_created"], 1)
                        self.assertEqual(state["state"], "VISIBLE")
                    self.assertEqual(call("quit").returncode, 0)
                    self.assertEqual(process.wait(timeout=5), 0)
                    self.assertFalse(has_owner(application_id(folder)))
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=3)

    def test_adapter_local_matrix(self):
        from app import Application, Sidebar
        from core import arguments
        from gi.repository import GLib
        with tempfile.TemporaryDirectory() as folder:
            opts = arguments(["show", "--fixture", str(ROOT / "fixtures/chat.html"), "--profile-root", folder])
            app = Application(opts)
            panel = Sidebar(app)
            try:
                panel.show()
                app.state = "VISIBLE"
                context = GLib.MainContext.default()

                def wait(predicate):
                    deadline = time.monotonic() + 8
                    while not predicate():
                        if time.monotonic() > deadline:
                            self.fail("adapter fixture timed out")
                        if context.pending(): context.iteration(False)
                        else: time.sleep(0.01)

                def js(source, world=None):
                    values = []
                    def finished(view, result, _data):
                        values.append(view.evaluate_javascript_finish(result).to_json(0))
                    panel.view.evaluate_javascript(source, -1, world, None, None, finished, None)
                    wait(lambda: bool(values))
                    return json.loads(values[0])

                wait(lambda: app.load_status == "FINISHED")
                reports = []
                panel.diagnostics_report(reports.append)
                wait(lambda: bool(reports))
                self.assertEqual(reports[0]["draft"], "PRESENT")
                self.assertEqual(reports[0]["generation"], "IDLE_CONTROL")
                self.assertEqual(reports[0]["main_count"], 1)
                self.assertNotIn("Unsent fixture text", json.dumps(reports[0]))
                # Prefix diagnostics must match whitespace, not a literal backslash.
                js("var probeHeader=document.createElement('header'); var probeModel=document.createElement('button'); probeModel.textContent='ChatGPT local'; probeHeader.append(probeModel); document.body.append(probeHeader); var probeSend=document.createElement('button'); probeSend.setAttribute('aria-label','Send local'); document.body.append(probeSend); var probeMenu=document.createElement('button'); probeMenu.setAttribute('aria-label','ChatGPT local'); probeMenu.setAttribute('aria-haspopup','menu'); document.body.append(probeMenu); true")
                reports.clear()
                panel.diagnostics_report(reports.append)
                wait(lambda: bool(reports))
                for field in ("model_text", "send_prefix", "model_menu"):
                    self.assertTrue(reports[0][field], field)
                js("probeModel.textContent='ChatGPTx'; probeSend.setAttribute('aria-label','Sendx'); probeMenu.setAttribute('aria-label','ChatGPTx'); var fixtureSend=document.querySelector('[aria-label=\"Send message\"]'); fixtureSend.setAttribute('aria-label','Fixture action'); true")
                reports.clear()
                panel.diagnostics_report(reports.append)
                wait(lambda: bool(reports))
                for field in ("model_text", "send_prefix", "model_menu"):
                    self.assertFalse(reports[0][field], field)
                js("fixtureSend.setAttribute('aria-label','Send message'); probeHeader.remove(); probeSend.remove(); probeMenu.remove(); true")
                js("document.querySelector('#draft').value=''; true")
                reports.clear()
                panel.diagnostics_report(reports.append)
                wait(lambda: bool(reports))
                self.assertEqual(reports[0]["draft"], "EMPTY")
                js("document.querySelector('#draft').value='Unsent fixture text'; true")
                panel.set_reduction(True)
                wait(lambda: app.reduction == "ENABLED")
                self.assertEqual(js("document.querySelectorAll('[data-chatgpt-lite-hidden]').length"), 2)
                js("var optionalInput=document.createElement('input'); optionalInput.setAttribute('aria-label','Suggestions'); document.querySelector('main').append(optionalInput); var requiredAside=document.createElement('aside'); requiredAside.setAttribute('aria-label','Promotions'); requiredAside.innerHTML='<div><div role=menu><button>Required local nested action</button></div></div>'; document.querySelector('main').append(requiredAside); true")
                js("globalThis.__chatgptLiteAdapterV1.apply(); true", "chatgpt-lite")
                self.assertFalse(js("optionalInput.hasAttribute('data-chatgpt-lite-hidden')"))
                self.assertFalse(js("requiredAside.hasAttribute('data-chatgpt-lite-hidden')"))
                js("optionalInput.remove(); requiredAside.remove(); true")
                screenshot = os.environ.get("CHATGPT_LITE_REDUCTION_SNAPSHOT")
                if screenshot:
                    from gi.repository import WebKit
                    done = []
                    def captured(view, result, _data):
                        texture = view.get_snapshot_finish(result)
                        texture.save_to_png(screenshot)
                        done.append(True)
                    panel.view.get_snapshot(WebKit.SnapshotRegion.VISIBLE, WebKit.SnapshotOptions.NONE,
                                            None, captured, None)
                    wait(lambda: bool(done))
                js("var outer=document.createElement('main'); var inner=document.querySelector('main'); inner.replaceWith(outer); outer.append(inner); true")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.apply().reduction", "chatgpt-lite"), "ENABLED")
                js("var extra=document.createElement('main'); document.body.append(extra); true")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.apply().reduction", "chatgpt-lite"), "DEGRADED")
                js("extra.remove(); outer.replaceWith(inner); true")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.apply().reduction", "chatgpt-lite"), "ENABLED")
                self.assertEqual(js("getComputedStyle(document.querySelector('[role=dialog]')).display"), "block")
                self.assertEqual(js("document.querySelector('#draft').value"), "Unsent fixture text")
                js("globalThis.__chatgptLiteAdapterV1.apply(); true", "chatgpt-lite")
                self.assertEqual(js("document.querySelectorAll('[data-chatgpt-lite-hidden]').length"), 2)
                self.assertEqual(js("document.querySelectorAll('style[data-chatgpt-lite-style]').length"), 1)
                js("document.querySelector('main').className='changed-generated-class'; true")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.apply().reduction", "chatgpt-lite"), "ENABLED")
                js("var a=document.createElement('aside'); a.setAttribute('aria-label','Auxiliary panel'); document.querySelector('main').append(a); true")
                wait(lambda: js("document.querySelectorAll('[data-chatgpt-lite-hidden]').length") == 3)
                panel.set_reduction(False)
                wait(lambda: app.reduction == "DISABLED")
                self.assertEqual(js("document.querySelectorAll('[data-chatgpt-lite-hidden]').length"), 0)
                self.assertEqual(js("document.querySelectorAll('style[data-chatgpt-lite-style]').length"), 0)
                self.assertEqual(js("document.querySelector('#draft').value"), "Unsent fixture text")
                js("document.querySelector('[role=log]').remove(); true")
                panel.set_reduction(True)
                wait(lambda: app.reduction == "ENABLED")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.describe().page", "chatgpt-lite"), "CHAT_HOME")
                js("document.querySelector('[aria-label=\"Model selector\"]').setAttribute('aria-label','Unknown model control'); true")
                wait(lambda: js("document.querySelectorAll('[data-chatgpt-lite-hidden]').length") == 0)
                wait(lambda: app.reduction == "DEGRADED")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.describe().page", "chatgpt-lite"), "UNKNOWN")
                js("document.querySelector('[aria-label=\"Unknown model control\"]').setAttribute('aria-label','Выбор модели'); document.querySelector('[aria-label=\"New chat\"]').setAttribute('aria-label','Новый чат'); document.querySelector('[aria-label=\"Send message\"]').setAttribute('aria-label','Отправить сообщение'); true")
                wait(lambda: app.reduction == "ENABLED")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.describe().page", "chatgpt-lite"), "CHAT_HOME")
                js("var old=document.querySelector('#draft'); var edit=document.createElement('div'); edit.contentEditable='true'; edit.setAttribute('role','textbox'); edit.id='draft'; old.replaceWith(edit); true")
                reports.clear()
                panel.diagnostics_report(reports.append)
                wait(lambda: bool(reports))
                self.assertEqual(reports[0]["editable_count"], 1)
                self.assertTrue(reports[0]["editor_in_form"])
                self.assertEqual(reports[0]["draft"], "EMPTY")
                js("edit.append(document.createTextNode('private local canary')); true")
                reports.clear()
                panel.diagnostics_report(reports.append)
                wait(lambda: bool(reports))
                self.assertEqual(reports[0]["draft"], "PRESENT")
                self.assertNotIn("private local canary", json.dumps(reports[0]))
                app.panel = panel
                self.assertEqual(app.dispatch("reload")[1], 2)  # Nonempty contenteditable.
                js("edit.replaceChildren(); true")
                self.assertEqual(app.dispatch("reload")[1], 0)
                wait(lambda: app.load_status == "FINISHED")
                js("var p=document.createElement('input'); p.type='password'; document.body.append(p); true")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.apply().page", "chatgpt-lite"), "AUTHENTICATION")
                self.assertEqual(js("document.querySelectorAll('[data-chatgpt-lite-hidden]').length"), 0)
                js("p.remove(); var security=document.createElement('div'); security.setAttribute('data-security-verification',''); document.body.append(security); true")
                self.assertEqual(js("globalThis.__chatgptLiteAdapterV1.apply().page", "chatgpt-lite"), "SECURITY_VERIFICATION")
                self.assertEqual(js("document.querySelectorAll('[data-chatgpt-lite-hidden]').length"), 0)
            finally:
                panel.destroy()

    def test_host_pipe_bounded_input_and_external_state(self):
        with tempfile.TemporaryDirectory() as folder:
            command = [sys.executable, str(ROOT / "app.py"), "show", "--host-pipe", "--fixture",
                       str(ROOT / "fixtures/chat.html"), "--profile-root", folder]
            with tempfile.TemporaryFile() as log:
                # select() observes the descriptor, not BufferedReader's prefetched
                # frames. Raw stdout prevents a buffered frame from looking absent.
                process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, bufsize=0)
                try:
                    def frame(state):
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            ready, _, _ = select.select([process.stdout], [], [], 1)
                            if ready:
                                line = process.stdout.readline()
                                if not line: self.fail("host process exited early")
                                value = json.loads(line)
                                if value.get("state") == state: return
                        self.fail("host state timed out")
                    frame("VISIBLE")
                    duplicate = subprocess.run(command, capture_output=True, text=True, timeout=5)
                    self.assertEqual(duplicate.returncode, 3)
                    # External native commands must update the host's state too.
                    external = [sys.executable, str(ROOT / "app.py"), "hide", "--fixture",
                                str(ROOT / "fixtures/chat.html"), "--profile-root", folder]
                    self.assertEqual(subprocess.run(external, capture_output=True, timeout=5).returncode, 0)
                    frame("HIDDEN")
                    process.stdin.write(b"show\n"); process.stdin.flush(); frame("VISIBLE")
                    for _ in range(3):
                        process.stdin.write(b"hide\n"); process.stdin.flush(); frame("HIDDEN")
                        process.stdin.write(b"show\n"); process.stdin.flush(); frame("VISIBLE")
                    # Invalid/incomplete frames cannot grow memory indefinitely.
                    process.stdin.write(b"x" * 1100); process.stdin.flush()
                    self.assertEqual(process.wait(timeout=8), 0)
                    process.stdin.close()
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=3)
                    if not process.stdin.closed: process.stdin.close()
                    process.stdout.close()
                eof_process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, bufsize=0)
                try:
                    ready, _, _ = select.select([eof_process.stdout], [], [], 10)
                    self.assertTrue(ready)
                    self.assertEqual(json.loads(eof_process.stdout.readline())["state"], "VISIBLE")
                    eof_process.stdin.close()
                    self.assertEqual(eof_process.wait(timeout=8), 0)
                finally:
                    if eof_process.poll() is None:
                        eof_process.terminate()
                        eof_process.wait(timeout=3)
                    if not eof_process.stdin.closed: eof_process.stdin.close()
                    eof_process.stdout.close()

    def test_cookie_survives_full_process_restart(self):
        with tempfile.TemporaryDirectory() as folder:
            command = [sys.executable, str(Path(__file__)), "--cookie-worker", folder]
            for mode in ("write", "read"):
                result = subprocess.run([*command, mode], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("FIXTURE_COOKIE_OK", result.stdout)
            cookie_file = Path(folder) / "data/cookies.sqlite"
            self.assertTrue(cookie_file.is_file())
            self.assertEqual(cookie_file.stat().st_mode & 0o777, 0o600)


def cookie_worker(folder, mode):
    from app import Application, Sidebar
    from core import arguments
    import gi
    gi.require_version("Soup", "3.0")
    from gi.repository import GLib, Soup
    opts = arguments(["show", "--fixture", str(ROOT / "fixtures/baseline.html"),
                      "--profile-root", folder])
    panel = Sidebar(Application(opts))
    manager = panel.session.get_cookie_manager()
    done, errors = [], []

    def finished(cookie_manager, result, _data):
        try:
            if mode == "write":
                assert cookie_manager.add_cookie_finish(result)
            else:
                cookies = cookie_manager.get_cookies_finish(result)
                assert any(c.get_name() == "local-fixture" and c.get_value() == "inert-test-value" for c in cookies)
            done.append(True)
        except Exception:
            errors.append(True)

    try:
        if mode == "write":
            cookie = Soup.Cookie.new("local-fixture", "inert-test-value", "fixture.invalid", "/", 86400)
            cookie.set_secure(True)
            cookie.set_http_only(True)
            manager.add_cookie(cookie, None, finished, None)
        else:
            manager.get_cookies("https://fixture.invalid/", None, finished, None)
        deadline = time.monotonic() + 10
        context = GLib.MainContext.default()
        while not done and not errors:
            if time.monotonic() > deadline:
                raise RuntimeError("fixture cookie operation timed out")
            if context.pending():
                context.iteration(False)
            else:
                time.sleep(0.01)
        if errors:
            raise RuntimeError("fixture cookie check failed")
        print("FIXTURE_COOKIE_OK")
    finally:
        panel.destroy()


if __name__ == "__main__" and "--cookie-worker" in sys.argv:
    cookie_worker(sys.argv[2], sys.argv[3])
