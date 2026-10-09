# Engine-selection handoff

## Goal and unresolved first step

Select an embedded engine that can render the original ChatGPT website in the
existing Omarchy QML shell with usable responsiveness and substantially lower
memory. No engine is accepted. Preserve existing native integration and private
profiles; do not substitute an API client or a rewritten chat UI.

## Candidates

**Chromium:** historical implementation only. It failed the intended lighter
engine direction. Its source remains for reference and existing data remains local.

**WPE WebKit:** integrated native adapter, but observed memory did not establish
threefold reduction or a 200 MiB working-chat result. Not selected.

**Servo:** an unoptimized local v0.7.0 experiment with native frame/input transport,
Reload, owned-engine Restart and periodic cookie checkpoints. User reports include
severe slowness, approximately 1 GiB at login, repeated login and an overlapping
left page strip after Reload. No complete repair or working-chat acceptance.
Related/OAuth windows, files, clipboard and composition are incomplete. Synthetic
checks do not establish actual login retention or site fidelity.

**Other probes:** Blitz refused the actual site with HTTP403. Aurora failed to
build; Spiral/Gosub were not usable full-site browsers. These are negative
observations, not a comprehensive ranking.

## Saved source and local state

The pre-cleanup checkpoint is `0bb0a410255bda7117d9377e22f745b1aa464b75`.
The [Servo archive](../engines/servo/README.md) includes the complete 12-file diff
against pinned upstream and the modified gaol source. It does not include the
multi-gigabyte build tree, engine executable or private profile.

The installed local plugin uses `servo-candidate-08/ServoService.qml`. Source
`manifest.json` still points to `native/Service.qml`; these are not identical
installations. No runtime change is part of this repository cleanup.

The original local Servo workspace is
`~/.local/share/chatgpt-servo-repair-Ar9ArjX8`. It remains untouched for recovery.
Private historical reports and generated checkout outputs were moved to
`~/.hygiene/omarchy-chatgpt-lite/save-clean-20261009/local-archive/`.

## Scope of this checkpoint

Engine development, builds, tests and security-review campaigns are paused at the
user's request. Existing guards are preserved, not disabled. Existing test source
is retained rather than destroyed. No background optimization campaign is running.
The next work should resolve engine feasibility before expanding ancillary
verification or claiming a finished plugin. No live-site functionality,
performance or release-readiness claim follows from a successful GitHub push.
