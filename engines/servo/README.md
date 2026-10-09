# Archived Servo experiment

This directory saves the local experiment, not a selected or supported engine.

- `servo.patch`: all 12 differences against Servo revision
  `aac43a3f31a259f04a574f5ec4e959c943ad7cc7` (v0.7.0 source archive).
- `gaol/`: the modified gaol 0.2.1 source and upstream licenses.
- `live-launch.mjs`: the original machine-specific development launcher.
- `live-identity.json`: the expected local binary checksum, not the binary.
- `engine.service.example`: the original machine-specific user unit, not an installer.
- `snapshot.json`: source provenance and changed paths.

To recover the source, obtain the pinned Servo revision and apply `servo.patch`
from its root with `git apply`. The original build mounted `gaol/` at
`/gaol-narrow`; that path is retained in the patch rather than claiming a new
portable build. No build or test was run for this archive. The launcher and unit
refer to local development paths and require deliberate adaptation elsewhere.
They must not be run as a generic installer.

The native transport and QML modules remain in the plugin's `native/` directory.
The experiment did not meet the working-chat memory or responsiveness goals.
Original-site visual fidelity, login persistence and full functionality remain
unaccepted. The reported left page strip after Reload remains unresolved.

No engine executable, compiled dependency, browser profile, credential, account
capture or private development log is included. Servo's MPL-2.0 and gaol's
MIT/Apache-2.0 licenses are preserved. The plugin's own licensing status is
unchanged.
