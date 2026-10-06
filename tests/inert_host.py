"""Inert pipe helper for actual QML bridge checks; no GTK/profile/network."""
import json
import sys

def state(value):
    print(json.dumps({"schema": 1, "state": value, "reduction": "DISABLED"}), flush=True)

state("VISIBLE")
for line in sys.stdin:
    command = line.strip()
    if command == "quit":
        break
    if command in ("show", "hide"):
        state("VISIBLE" if command == "show" else "HIDDEN")
