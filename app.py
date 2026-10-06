#!/usr/bin/python
"""Original ChatGPT sidebar; production reduction requires verified structure."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys

# Omarchy watches the installed tree: even CLI imports must never write pyc.
sys.dont_write_bytecode = True

from core import (
    application_id, arguments, bounded_width, private_directory, profile_paths,
    read_config, reload_safe, safe_navigation, transition, write_config,
)

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix


def has_owner(app_id):
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    result = connection.call_sync(
        "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
        "NameHasOwner", GLib.Variant("(s)", (app_id,)), GLib.VariantType("(b)"),
        Gio.DBusCallFlags.NONE, 2000, None,
    )
    return result.unpack()[0]


class Application(Gio.Application):
    def __init__(self, options, panel_factory=None):
        super().__init__(application_id=application_id(options.profile_root),
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.options = options
        self.paths = profile_paths(test_root=options.profile_root)
        self.state = "STOPPED"
        self.panel = None
        self.panel_factory = panel_factory or Sidebar
        self.view_creations = 0
        self.reduction = "DISABLED"
        self.load_status = "NOT_STARTED"
        self.host_pipe = None
        self.stopping = False

    def do_startup(self):
        Gio.Application.do_startup(self)
        if self.options.host_pipe:
            from hostpipe import HostPipe
            self.host_pipe = HostPipe(self)

    def notify_state(self):
        if self.host_pipe:
            self.host_pipe.state()

    def do_command_line(self, command_line):
        try:
            options = arguments(command_line.get_arguments()[1:])
            if options.host_pipe and command_line.get_is_remote():
                return 3
            if options.fixture != self.options.fixture or options.profile_root != self.options.profile_root:
                raise ValueError("instance options must match the running application")
            output, result = self.dispatch(options.command)
            if output:
                command_line.print_literal(output + "\n")
            return result
        except Exception:
            # Never include exception text: WebKit errors can contain sensitive URLs.
            command_line.printerr_literal("Command failed; no page data was logged.\n")
            return 1

    def dispatch(self, command):
        if command == "diagnostics":
            if self.panel is None:
                return json.dumps({"schema": 1, "error": "NOT_RUNNING"}), 0
            report = self.wait_diagnostics()
            return json.dumps(report), 2 if "error" in report else 0
        if command == "status":
            return json.dumps({"state": self.state, "pid": os.getpid(),
                               "primary_views_created": self.view_creations,
                               "reduction": self.reduction,
                               "load_status": self.load_status}), 0
        if command in ("lite-on", "lite-off"):
            config = read_config(self.paths)
            config["lite_requested"] = command == "lite-on"
            write_config(self.paths, config)
            self.reduction = "DEGRADED" if config["lite_requested"] else "DISABLED"
            if self.panel and hasattr(self.panel, "set_reduction"):
                self.panel.set_reduction(config["lite_requested"])
            self.notify_state()
            return ("Reduction requested; unverified production structure keeps the original presentation."
                    if config["lite_requested"] else "Original presentation requested; no filters enabled."), 0
        if command == "reload":
            if not self.panel:
                return "", 0
            report = self.wait_diagnostics()
            if self.panel and reload_safe(report, self.load_status, len(getattr(self.panel, "children", []))):
                self.load_status = "LOADING"
                self.panel.view.reload()
                return "Reload requested after empty-draft/idle recognized-page checks.", 0
            return "Reload deferred: draft and streaming safety NOT_VERIFIED.", 2
        next_state = transition(self.state, command)
        if next_state == "STOPPED":
            self.stop()
        elif next_state == "VISIBLE":
            if self.panel is None:
                panel = self.panel_factory(self)
                try:
                    panel.show()
                except Exception:
                    panel.destroy()
                    raise
                self.panel = panel
                self.view_creations += 1
                self.hold()
            elif self.state != "VISIBLE":
                self.panel.show()
            self.state = "VISIBLE"
        elif next_state == "HIDDEN":
            if self.state == "VISIBLE":
                self.panel.hide()
            self.state = "HIDDEN"
        self.notify_state()
        return "", 0

    def wait_diagnostics(self):
        if not self.panel or not hasattr(self.panel, "diagnostics_report"):
            return {"schema": 1, "error": "UNAVAILABLE"}
        results = []
        loop = GLib.MainLoop()
        active = True
        def completed(report):
            if active:
                results.append(report)
                loop.quit()
        self.panel.diagnostics_report(completed)
        if not results:
            timer = GLib.timeout_add(2000, lambda: (loop.quit(), False)[1])
            loop.run()
            if results:
                GLib.source_remove(timer)
        active = False
        return results[0] if results else {"schema": 1, "error": "TIMEOUT"}

    def stop(self):
        if self.stopping:
            return
        self.stopping = True
        if self.host_pipe:
            self.host_pipe.close()
        if self.panel:
            self.panel.destroy()
            self.panel = None
            self.release()
        self.state = "STOPPED"
        self.notify_state()
        self.quit()


class Sidebar:
    def __init__(self, app):
        # Load layer-shell before GTK so its interposition is available.
        gi.require_version("Gtk4LayerShell", "1.0")
        from gi.repository import Gtk4LayerShell
        gi.require_version("Gtk", "4.0")
        gi.require_version("Gdk", "4.0")
        gi.require_version("WebKit", "6.0")
        from gi.repository import Gdk, Gtk, WebKit
        self.Gtk, self.Gdk, self.WebKit, self.Layer = Gtk, Gdk, WebKit, Gtk4LayerShell
        self.app = app
        self.fixture = app.options.fixture is not None
        self.children = []
        self.child_ready = set()
        self.focus_seen = False
        self.focus_armed = False
        self.focus_timer = None
        self.escape_pending = False
        self.config = read_config(app.paths)
        app.reduction = "DEGRADED" if self.config["lite_requested"] else "DISABLED"
        Gtk.init()
        if not self.fixture and not Gtk4LayerShell.is_supported():
            raise RuntimeError("Wayland layer-shell unavailable")
        os.umask(0o077)
        for path in app.paths.values():
            private_directory(path)
        self.session = WebKit.NetworkSession.new(str(app.paths["data"]), str(app.paths["cache"]))
        cookie_file = app.paths["data"] / "cookies.sqlite"
        # Refuse unsafe existing storage before handing its filename to WebKit.
        if cookie_file.is_symlink() or (cookie_file.exists() and
                (not cookie_file.is_file() or cookie_file.stat().st_uid != os.getuid()
                 or cookie_file.stat().st_mode & 0o077 or cookie_file.stat().st_nlink != 1)):
            raise ValueError("unsafe cookie storage")
        self.session.get_cookie_manager().set_persistent_storage(
            str(cookie_file), WebKit.CookiePersistentStorage.SQLITE)
        self.session.connect("download-started", lambda _session, download: download.cancel())
        self.adapter_source = (Path(__file__).parent / "reduction/adapter.js").read_text()
        self.adapter_generation = 0
        self.adapter_ready = False
        content = WebKit.UserContentManager()
        content.register_script_message_handler("liteState", "chatgpt-lite")
        content.connect("script-message-received::liteState", self.adapter_state)
        content.add_script(WebKit.UserScript.new_for_world(
            self.adapter_source, WebKit.UserContentInjectedFrames.TOP_FRAME,
            WebKit.UserScriptInjectionTime.END, "chatgpt-lite", None, None))
        self.view = WebKit.WebView(network_session=self.session, user_content_manager=content)
        self.window = Gtk.Window(title="ChatGPT Lite", decorated=False)
        self.window.set_child(self.view)
        self.window.connect("close-request", self.close_requested)
        self.window.connect("notify::is-active", self.focus_changed)
        self.keys = Gtk.EventControllerKey()
        self.keys.set_propagation_phase(Gtk.PropagationPhase.BUBBLE)
        self.keys.connect("key-pressed", self.key_pressed)
        self.window.add_controller(self.keys)
        self.interaction_keys = Gtk.EventControllerKey()
        self.interaction_keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        self.interaction_keys.connect("key-pressed", self.interacted)
        self.window.add_controller(self.interaction_keys)
        self.clicks = Gtk.GestureClick.new()
        self.clicks.set_button(0)
        self.clicks.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        self.clicks.connect("pressed", self.interacted)
        self.window.add_controller(self.clicks)
        self.view.connect("close", lambda _view: app.dispatch("hide"))
        self.view.connect("load-changed", self.loaded)
        self.view.connect("load-failed", self.failed)
        self.view.connect("web-process-terminated", self.terminated)
        self.connect_view(self.view)
        if not self.fixture:
            Gtk4LayerShell.init_for_window(self.window)
            Gtk4LayerShell.set_namespace(self.window, "omarchy-chatgpt-lite")
            Gtk4LayerShell.set_layer(self.window, Gtk4LayerShell.Layer.TOP)
            for edge in (Gtk4LayerShell.Edge.TOP, Gtk4LayerShell.Edge.BOTTOM, Gtk4LayerShell.Edge.RIGHT):
                Gtk4LayerShell.set_anchor(self.window, edge, True)
            Gtk4LayerShell.set_exclusive_zone(self.window, 0)
            Gtk4LayerShell.set_keyboard_mode(self.window, Gtk4LayerShell.KeyboardMode.ON_DEMAND)
        uri = app.options.fixture.as_uri() if self.fixture else "https://chatgpt.com"
        self.view.load_uri(uri)

    def adapter_state(self, _manager, value):
        raw = value.to_string()
        if len(raw) > 256:
            return
        try:
            result = json.loads(raw)
        except ValueError:
            return
        if isinstance(result, dict) and result.get("reduction") in {"DISABLED", "ENABLED", "DEGRADED"}:
            self.app.reduction = result["reduction"]
            self.app.notify_state()

    def evaluate_adapter(self, expression, callback):
        generation = self.adapter_generation
        script = expression if self.adapter_ready else self.adapter_source + ";\n" + expression

        def finished(view, result, _data):
            if generation != self.adapter_generation:
                return
            try:
                value = view.evaluate_javascript_finish(result)
                callback(json.loads(value.to_json(0)))
            except (GLib.Error, ValueError):
                callback(None)

        self.view.evaluate_javascript(script, -1, "chatgpt-lite", None, None, finished, None)

    def set_reduction(self, enabled):
        self.config["lite_requested"] = enabled
        # No fixture success can authorize production changes. The metadata is
        # deliberately false until real structural and compatibility evidence.
        metadata = json.loads((Path(__file__).parent / "reduction/verification.json").read_text())
        allowed = self.fixture or (metadata.get("live_structure_verified") is True
                                   and metadata.get("live_compatibility") == "LIVE_VERIFIED")
        if enabled and not allowed:
            self.app.reduction = "DEGRADED"
            self.app.notify_state()
            return
        def applied(result):
            self.app.reduction = result.get("reduction", "DEGRADED") if isinstance(result, dict) else "DEGRADED"
            self.app.notify_state()
        self.evaluate_adapter("globalThis.__chatgptLiteAdapterV1.setEnabled(" + ("true" if enabled else "false") + ")", applied)

    def diagnostics_report(self, callback):
        # Read reviewed source on demand so diagnostic improvements do not require
        # another page reload. Nothing is injected into the application world.
        source = (Path(__file__).parent / "reduction/diagnostics.js").read_text()
        def described(value):
            counts = ("main_count", "textarea_count", "editable_count", "textbox_count",
                      "form_count", "header_count", "nav_count", "log_count",
                      "submit_count", "header_menu_count", "form_button_count",
                      "form_named_count", "form_testid_count", "menu_count")
            flags = ("prompt_id", "send_testid", "stop_testid", "model_testid",
                     "send_named", "new_chat_named", "model_named", "nested_mains",
                     "editor_in_main", "editor_in_form", "composer_submit", "model_menu", "new_chat_link",
                     "voice_testid", "composer_submit_id", "model_text", "send_prefix", "voice_named")
            if not isinstance(value, dict):
                callback({"schema": 1, "error": "UNAVAILABLE"})
                return
            report = {"schema": 1}
            report.update({k: value[k] if type(value.get(k)) is int and 0 <= value[k] <= 16
                           else None for k in counts})
            report.update({k: value[k] if type(value.get(k)) is bool else None for k in flags})
            report["recognized_page"] = value.get("recognized_page") if value.get("recognized_page") in {"AUTHENTICATION", "SECURITY_VERIFICATION", "CHAT_HOME", "CONVERSATION", "UNKNOWN"} else "UNKNOWN"
            report["draft"] = value.get("draft") if value.get("draft") in {"EMPTY", "PRESENT", "UNKNOWN"} else "UNKNOWN"
            report["generation"] = value.get("generation") if value.get("generation") in {"ACTIVE", "IDLE_CONTROL", "UNKNOWN"} else "UNKNOWN"
            callback(report)
        self.evaluate_adapter(source, described)

    def structure_report(self, callback):
        # Closed schema of booleans/enums only, never arbitrary DOM values.
        def described(value):
            pages = {"AUTHENTICATION", "SECURITY_VERIFICATION", "CHAT_HOME", "CONVERSATION", "UNKNOWN"}
            keys = {"composer", "action", "model", "new_chat", "conversation"}
            if not isinstance(value, dict) or value.get("page") not in pages:
                callback({"page": "UNKNOWN"})
                return
            callback({"page": value["page"], **{key: value.get(key) is True for key in keys}})
        self.evaluate_adapter("globalThis.__chatgptLiteAdapterV1.describe()", described)

    def connect_view(self, view):
        view.connect("create", self.create_child)
        view.connect("decide-policy", self.decide_policy)
        view.connect("permission-request", self.permission_request)
        # Native context menus, option menus, script dialogs and TLS handling
        # retain their defaults. Escape dismisses the panel only without page
        # overlays/streaming; linked windows remain native transient windows.

    def permission_request(self, _view, request):
        # Media, device and location access are outside this baseline's scope.
        # Normal WebKit handling remains in place for unrelated permissions.
        types = [getattr(self.WebKit, name, None) for name in (
            "UserMediaPermissionRequest", "DeviceInfoPermissionRequest",
            "GeolocationPermissionRequest", "NotificationPermissionRequest",
        )]
        if any(kind is not None and isinstance(request, kind) for kind in types):
            request.deny()
            return True
        return False

    def decide_policy(self, _view, decision, kind):
        if kind not in (self.WebKit.PolicyDecisionType.NAVIGATION_ACTION,
                        self.WebKit.PolicyDecisionType.NEW_WINDOW_ACTION):
            return False
        uri = decision.get_navigation_action().get_request().get_uri()
        if not safe_navigation(uri, self.fixture):
            decision.ignore()
            return True
        return False

    def create_child(self, source, action):
        uri = action.get_request().get_uri()
        from urllib.parse import urlsplit
        parsed = urlsplit(uri)
        # Do not create another main ChatGPT tab. Required auth paths remain
        # eligible; their actual compatibility needs interactive verification.
        if (not safe_navigation(uri, self.fixture) or len(self.children) >= 3
                or (parsed.hostname == "chatgpt.com" and
                    (parsed.path in ("", "/") or parsed.path.startswith("/c/")))):
            return None
        view = self.WebKit.WebView(related_view=source)
        window = self.Gtk.Window(title="ChatGPT — linked window", transient_for=self.window)
        window.set_default_size(620, 720)
        window.set_child(view)
        self.children.append(window)
        self.connect_view(view)
        view.connect("ready-to-show", lambda _view: self.child_show(window))
        view.connect("close", lambda _view: self.child_close(window))
        window.connect("close-request", lambda _window: self.child_close(window))
        window.connect("notify::is-active", self.focus_changed)
        child_keys = self.Gtk.EventControllerKey()
        child_keys.set_propagation_phase(self.Gtk.PropagationPhase.CAPTURE)
        child_keys.connect("key-pressed", self.interacted)
        window.add_controller(child_keys)
        child_clicks = self.Gtk.GestureClick.new()
        child_clicks.set_button(0)
        child_clicks.set_propagation_phase(self.Gtk.PropagationPhase.CAPTURE)
        child_clicks.connect("pressed", self.interacted)
        window.add_controller(child_clicks)
        return view

    def child_show(self, window):
        self.child_ready.add(window)
        if self.app.state == "VISIBLE":
            window.present()

    def child_close(self, window):
        if self.app.state == "VISIBLE" and self.focus_armed and self.focus_timer is None:
            self.focus_timer = GLib.timeout_add(150, self.dismiss_unfocused)
        self.child_ready.discard(window)
        if window in self.children:
            self.children.remove(window)
            window.destroy()
        return True

    def active_monitor(self):
        display = self.Gdk.Display.get_default()
        monitors = display.get_monitors()
        if self.fixture:
            return monitors.get_item(0)
        result = subprocess.run(["/usr/bin/hyprctl", "-j", "monitors"], capture_output=True,
                                timeout=2, check=True)
        if len(result.stdout) > 65536:
            raise ValueError("monitor response too large")
        focused = next((row["name"] for row in json.loads(result.stdout) if row.get("focused") is True), None)
        for index in range(monitors.get_n_items()):
            monitor = monitors.get_item(index)
            if monitor.get_connector() == focused:
                return monitor
        raise RuntimeError("active monitor not found")

    def show(self):
        monitor = self.active_monitor()
        if monitor is None:
            raise RuntimeError("no monitor")
        geometry = monitor.get_geometry()
        if not self.fixture:
            self.Layer.set_monitor(self.window, monitor)
        self.window.set_default_size(bounded_width(self.config["width"], geometry.width), geometry.height)
        self.focus_armed = False
        self.window.present()
        self.view.grab_focus()
        for window in self.child_ready:
            window.present()

    def hide(self):
        self.focus_seen = False
        self.focus_armed = False
        if self.focus_timer is not None:
            GLib.source_remove(self.focus_timer)
            self.focus_timer = None
        for window in self.children:
            window.set_visible(False)
        self.window.set_visible(False)

    def key_pressed(self, _controller, keyval, _keycode, modifiers):
        if keyval != self.Gdk.KEY_Escape or modifiers or self.children or self.escape_pending:
            return False
        self.escape_pending = True
        generation = self.adapter_generation
        def checked(result):
            self.escape_pending = False
            if (result is True and generation == self.adapter_generation
                    and self.app.state == "VISIBLE"):
                self.app.dispatch("hide")
        # Bubble after the original site: handled Escape never reaches this
        # controller. Inspect only fixed structural
        # signals; preserve menus, fullscreen, IME and cancellation behavior.
        self.evaluate_adapter("""(() => {
          const visible = s => [...document.querySelectorAll(s)].some(e => e.getClientRects().length);
          const stop = [...document.querySelectorAll('button,[role="button"]')].some(e =>
            /^(stop( generating)?|остановить( генерацию)?)$/i.test(e.getAttribute('aria-label') || ''));
          return !document.fullscreenElement && !stop &&
            !visible('[role="dialog"],[role="menu"],[role="listbox"],[aria-modal="true"],dialog[open],[data-testid="stop-button"],[aria-expanded="true"]');
        })()""", checked)
        return False

    def interacted(self, _controller, *_args):
        # Launcher/ON_DEMAND focus handoff is not user dismissal. Only arm
        # outside-focus hiding after a click/key in this owned window group.
        if self.app.state == "VISIBLE":
            self.focus_armed = True
        return False

    def focus_changed(self, window, _property):
        if window.is_active():
            self.focus_seen = True
            if self.focus_timer is not None:
                GLib.source_remove(self.focus_timer)
                self.focus_timer = None
        elif self.focus_armed and self.app.state == "VISIBLE" and self.focus_timer is None:
            # One transition check, not polling. Allow native dialogs time to
            # acquire focus before deciding the user moved to another app.
            self.focus_timer = GLib.timeout_add(150, self.dismiss_unfocused)

    def dismiss_unfocused(self):
        self.focus_timer = None
        if self.app.state != "VISIBLE" or not self.focus_armed or self.window.is_active():
            return False
        windows = self.Gtk.Window.get_toplevels()
        for index in range(windows.get_n_items()):
            candidate = windows.get_item(index)
            if not candidate.is_active():
                continue
            seen = set()
            while candidate is not None and candidate not in seen:
                if candidate == self.window:
                    return False
                seen.add(candidate)
                candidate = candidate.get_transient_for()
        self.app.dispatch("hide")
        return False

    def close_requested(self, _window):
        self.app.dispatch("hide")
        return True

    def loaded(self, _view, event):
        if event == self.WebKit.LoadEvent.FINISHED and self.app.load_status != "FAILED":
            self.app.load_status = "FINISHED"
            self.adapter_ready = True
            if self.config["lite_requested"]:
                self.set_reduction(True)
        elif event == self.WebKit.LoadEvent.STARTED:
            self.escape_pending = False
            self.adapter_generation += 1
            self.adapter_ready = False
            self.app.load_status = "LOADING"

    def failed(self, _view, _event, _uri, _error):
        self.app.load_status = "FAILED"
        return False

    def terminated(self, _view, _reason):
        self.app.load_status = "WEB_PROCESS_TERMINATED"
        # Do not automatically reload or retry a submission.

    def destroy(self):
        self.adapter_generation += 1
        self.focus_seen = False
        self.focus_armed = False
        if self.focus_timer is not None:
            GLib.source_remove(self.focus_timer)
            self.focus_timer = None
        for window in list(self.children):
            self.child_close(window)
        self.view.stop_loading()
        self.window.destroy()


def main(argv=None):
    options = arguments(sys.argv[1:] if argv is None else argv)
    app_id = application_id(options.profile_root)
    if options.host_pipe and has_owner(app_id):
        print("Host ownership refused: application already running.", file=sys.stderr)
        return 3
    paths = profile_paths(test_root=options.profile_root)
    # Commands that should not create an application instance are resolved
    # before registration. Normal activation is arbitrated by GApplication.
    if options.command in ("hide", "quit", "reload", "status", "diagnostics", "lite-on", "lite-off") and not has_owner(app_id):
        if options.command in ("lite-on", "lite-off"):
            config = read_config(paths)
            config["lite_requested"] = options.command == "lite-on"
            write_config(paths, config)
            print("Preference saved; baseline keeps the original site without reduction.")
        elif options.command == "diagnostics":
            print(json.dumps({"schema": 1, "error": "NOT_RUNNING"}))
        elif options.command == "status":
            print(json.dumps({"state": "STOPPED", "primary_views_created": 0,
                              "reduction": "DISABLED", "load_status": "NOT_STARTED"}))
        return 0
    app = Application(options)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda *_: (app.stop(), False)[1])
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, lambda *_: (app.stop(), False)[1])
    return app.run([str(Path(__file__).resolve()), *(sys.argv[1:] if argv is None else argv)])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, GLib.Error):
        print("Startup failed. Check dependencies, private profile permissions and session D-Bus.", file=sys.stderr)
        sys.exit(1)
