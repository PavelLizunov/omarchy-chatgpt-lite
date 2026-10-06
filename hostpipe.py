"""Bounded, owning stdin lifecycle channel; no socket, HTTP service or polling."""

import json
import os

import gi

gi.require_version("GioUnix", "2.0")
from gi.repository import Gio, GioUnix, GLib

ALLOWED = {"show", "hide", "toggle", "quit", "lite-on", "lite-off", "status", "structure"}


class HostPipe:
    def __init__(self, app):
        self.app = app
        self.buffer = bytearray()
        self.cancellable = Gio.Cancellable()
        self.input = GioUnix.InputStream.new(0, False)
        self.closed = False
        os.set_blocking(1, False)
        self.read_next()

    def emit(self, payload):
        raw = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
        if len(raw) > 1024:
            return
        try:
            # One bounded state frame fits within PIPE_BUF; host must drain it.
            os.write(1, raw)
        except (BrokenPipeError, OSError):
            self.app.stop()

    def state(self):
        self.emit({"schema": 1, "state": self.app.state, "reduction": self.app.reduction})

    def read_next(self):
        if not self.closed:
            self.input.read_bytes_async(256, GLib.PRIORITY_DEFAULT, self.cancellable, self.received, None)

    def received(self, stream, result, _data):
        if self.closed:
            return
        try:
            chunk = stream.read_bytes_finish(result).get_data()
        except GLib.Error:
            self.app.stop()
            return
        if not chunk:
            self.app.stop()
            return
        self.buffer.extend(chunk)
        if len(self.buffer) > 1024:
            self.app.stop()
            return
        while b"\n" in self.buffer:
            line, _, rest = self.buffer.partition(b"\n")
            self.buffer = bytearray(rest)
            try:
                command = line.decode("ascii")
                if command not in ALLOWED:
                    raise ValueError("unsupported host command")
                if command == "structure":
                    if self.app.panel:
                        self.app.panel.structure_report(lambda report: self.emit({"schema": 1, "structure": report}))
                else:
                    self.app.dispatch(command)
                    self.state()
            except Exception:
                self.emit({"schema": 1, "error": "COMMAND_FAILED"})
        self.read_next()

    def close(self):
        self.closed = True
        self.cancellable.cancel()
