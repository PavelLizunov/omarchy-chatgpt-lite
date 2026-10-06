#!/usr/bin/python
"""Own a bounded Broadway Unix-socket display and private D-Bus test session."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="chatgpt-lite-check-") as folder:
        runtime = Path(folder)
        runtime.chmod(0o700)
        env = os.environ.copy()
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "BROADWAY_DISPLAY"):
            env.pop(key, None)
        for key in ("HYPRLAND_INSTANCE_SIGNATURE", "AT_SPI_BUS_ADDRESS"):
            env.pop(key, None)
        for key, subfolder in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                               ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"),
                               ("XDG_STATE_HOME", "state")):
            path = runtime / subfolder
            path.mkdir(mode=0o700)
            env[key] = str(path)
        env.update({"XDG_RUNTIME_DIR": str(runtime), "GDK_BACKEND": "broadway",
                    "BROADWAY_DISPLAY": ":17", "CHATGPT_LITE_TEST_BUS": "1",
                    "CHATGPT_LITE_TEST_WEBKIT": "1", "PYTHONDONTWRITEBYTECODE": "1",
                    "GTK_A11Y": "none", "GSETTINGS_BACKEND": "memory"})
        # No installed service directories: this test bus cannot auto-activate
        # desktop portals or helpers from the user's production configuration.
        bus_config = runtime / "bus.conf"
        bus_config.write_text('''<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow receive_sender="*" eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>\n''')
        # No TCP listener or external viewer. The server and logs are owned by
        # this foreground runner and cleaned up on success, failure or timeout.
        with tempfile.TemporaryFile() as log:
            server = subprocess.Popen(["/usr/bin/gtk4-broadwayd", "-u", str(runtime / "viewer.sock"), ":17"],
                                      env=env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 5
                while not (runtime / "broadway18.socket").exists():
                    if server.poll() is not None or time.monotonic() > deadline:
                        log.seek(0)
                        print(log.read().decode(errors="replace"), file=sys.stderr)
                        raise RuntimeError("owned Broadway display did not become ready")
                    time.sleep(0.02)
                test_process = subprocess.Popen(
                    ["/usr/bin/dbus-run-session", "--config-file", str(bus_config), "--",
                     "/usr/bin/python", "-m", "unittest", "discover", "-s", "tests", "-v"],
                    cwd=ROOT, env=env, start_new_session=True,
                )
                try:
                    return test_process.wait(timeout=90)
                finally:
                    # The session process group belongs exclusively to this run.
                    try:
                        os.killpg(test_process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    if test_process.poll() is None:
                        try:
                            test_process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            os.killpg(test_process.pid, signal.SIGKILL)
                            test_process.wait(timeout=3)
            finally:
                server.terminate()
                try:
                    server.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=3)


if __name__ == "__main__":
    sys.exit(main())
