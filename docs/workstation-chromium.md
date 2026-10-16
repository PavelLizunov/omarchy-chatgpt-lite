# Workstation Chromium activation — 2026-10-16

The user requested the existing small native ChatGPT popover for immediate use,
not a separate browser window, engine research or another memory campaign.

## Installed and loaded

- Installed ID: `slovn.chatgpt-lite`, local version `0.4.0-local-chromium`.
- Installed service: `native/ChromiumService.qml`, explicitly setting `useServo`
  and `useWpe` to false. The source manifest remains experimental and unchanged.
- One existing managed shell: `omarchy-qt612-native.service`, PID `1214359`.
- Host: pinned Quickshell 0.3.2, revision
  `4f508be500dea6e5732cc3d50382a0048b17e7b1`, existing argv0 compatibility patch.
  SHA-256: `57d5120d336a488053adcbfcc328976d843047547aadc2d61ffa77fa2b52303f`.
- The existing host package/hash guard was updated to the exact installed packages
  and passed. It was not bypassed. The previous host and plugin are restorable.
- Actual IPC: `QTWEBENGINE`, `BAR_POPOVER`, 460×560, `popup_visible: true`,
  `load_state: SUCCEEDED`, `startup_error: NONE`, `host_compatible: true`, one
  primary renderer PID `1216480`, no auxiliary windows, reduction disabled.
- Actual compositor layer: namespace `slovn-chatgpt-lite`, x910/y31,
  width460/height560, owned by the same shared-shell PID.
- The bar entry was enabled at right/index1. The popover was left open for use.

The current source had pre-existing uncommitted engine, documentation and comment
changes. They were preserved, not silently included in this task checkpoint.
The installed candidate uses that current Service/Browser implementation plus
this explicit Chromium entry and rebuilt native modules. QtQuick imports in the
installed compatibility copy select 6.11 under Qt 6.12, matching the desktop's
existing compatibility mechanism. This checkpoint is not a portable installer.

## Verification and limits

`node tests/chromium-service.mjs`, `node tests/lifecycle-checks.mjs`, the existing
native helper checks, speed-policy checks, manifest validation and compatibility
copy verification passed. The actual native Panel/Content/Browser inert fixture
rendered and its PNG was inspected: readable controls, contained browser and no
obvious clipping. The offscreen backend reported its known Vulkan/GPU warnings;
report-policy rendering is not strict GPU acceptance or live website coverage.

`SUCCEEDED` is navigation completion, not proof of authenticated conversation
rendering. Fresh inference, login, input, scrolling and reload acceptance remain
pending actual use. No messages were sent and no account-page image was captured.
No speculative performance flags, website patches, profile migration or memory
ceiling were added for this activation. Existing engine-scoped profile/cache paths
were retained. The shell was restarted once through its existing managed service;
no second shell or compositor restart was used.

The first enable/summon raced initial plugin discovery and returned unavailable;
after the same host finished initialization, enable and summon succeeded. This
is retained as an observed startup timing failure, not a hidden passing attempt.

Private installed snapshots, build products, inert preview and loaded IPC evidence
are under `~/.local/share/chatgpt-working-20261016/`, outside Git. A task checkpoint
push is source preservation only, not a release or Marketplace publication.
