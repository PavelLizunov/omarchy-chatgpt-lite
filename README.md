# ChatGPT Lite for Omarchy

Original [ChatGPT](https://chatgpt.com) in a native Omarchy top-bar popover,
using QtWebEngine/Chromium. This is not an API client or a replacement chat UI.

**Experimental source publication, not a production-ready release or Marketplace
submission.** A compatible host is required. Do not install into a shared shell
without reviewing the host requirements and lifecycle impact below.

## Interface

The chat-bubble widget belongs to the right bar section. A compact 460 × 560
logical-unit popup has outlined Expand/Compact controls. Resizing and hiding keep
one service-owned primary browser and persistent profile. Up to three linked
windows share the profile but have independent visibility; a visible linked
window can create another while the main popover is hidden.

Omarchy Color/Style tokens style the native frame. Appearance-only isolated CSS
is scoped to the top-level `https://chatgpt.com` page and excludes security-challenge
paths. Authentication-provider pages retain their original appearance. The
original website owns conversations, models, streaming, history and menus.
Native loading/error feedback occupies a separate strip, never covers the web
page, and disappears after successful loading. Chromium context-menu chrome is
suppressed; site-owned menus are not replaced.

## Requirements and safety

Observed development environment: Omarchy 4.0.4, Quickshell 0.3.1, Qt 6.11.2 and
QtWebEngine. Imports include QtQuick, QtWebEngine, QtQuick.Dialogs, Quickshell,
Quickshell.Io, and the installed `qs.Commons`/`qs.Ui` host modules.

The plugin runs unsandboxed with your user permissions inside the existing shared
Omarchy shell. It must not launch a second shell. Opening the browser contacts
ChatGPT and its providers using the ordinary browser stack. There is no provider
API key, application protocol interception, security bypass or script blocklist.

Quickshell versions that discard application arguments are incompatible:
QtWebEngine can abort such a host. Service checks the argument list before creating
a profile and reports `HOST_ARGUMENTS_EMPTY`. The development installation uses
a separately built, dependency/hash-guarded private host with
[native/host-argv.patch](native/host-argv.patch); system packages are unchanged.
This repository does **not** ship a host binary, installer for that host, systemd
unit, identity file or automatic host build. Inspect and build the compatible
upstream host independently. Do not treat the patch/launcher as turnkey setup.

Native profile preparation runs one bounded `/usr/bin/python -B` helper. User data
is stored in `${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-chatgpt-lite-qt/profile`
and cache in `${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-chatgpt-lite-qt/cache`, with
private directory checks. Clipboard reads require native confirmation. Downloads
require a user-chosen save path. Persistent profiles are not part of this repository.

## Installation status

The root manifest declares service and bar-widget entry points. Source defaults
leave the optional capture bridge disabled. The already tested development
installation contains an independent copy, not a source symlink.

`install-native.py` is a **migration/update helper for an existing disabled plugin**,
not a fresh-install command. It checks legacy runtime state, backs up the installed
copy, replaces known code files and manifest, rescans/enables the plugin and checks
IPC. This can unload shared-shell surfaces and lose ephemeral state. It requires
a compatible host and retains unknown user files. It does not install the optional
capture module. Do not invoke it with active unrelated drafts/jobs. Ordinary
installed local code changes must be reconciled rather than blindly overwritten.

`install.py`, root `Panel.qml`, `app.py`, `core.py`, `hostpipe.py`, `fixtures/` and
`reduction/` are preserved legacy GTK/WebKit sources. Their installer expected the
former panel-only manifest and is **not the install path for this native version**.
GTK/WebKit and the legacy reduction adapter are not used by the native entry points.

## Local checks

These commands use inert content and do not submit account messages:

```sh
python -B -m unittest discover -s tests -p 'test_native*.py' -v
python -B tests/live-evidence-policy.py
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  timeout 18 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_native.qml
omarchy plugin validate .
```

Omarchy host components in `tests/native-bar-preview.qml` require the optional
reviewed static-module adapter from [qml-preview-mcp](https://github.com/PavelLizunov/qml-preview-mcp).
That fixture uses synthetic HTML in the actual Chromium component. It is a
component regression, **not a screenshot of your ChatGPT account or live menu test**.
The capture bridge in `native/Capture.qml` is opt-in, built separately from that
repository, and limited to the existing primary browser with explicit image
consent. It does not click menus, capture linked windows or inspect page data.

## What has been checked

Local native Python/profile/installer checks and Qt input/retention tests pass.
Actual-component fixtures check native Expand/Compact with pointer and keyboard,
shared profile/draft retention, auxiliary ownership/admission and error-strip
geometry. An explicitly authorized genuine hidden ChatGPT primary image was
captured and inspected in the development installation without opening a window.

This does not establish full original-site compatibility. Physical compositor
focus/Escape/outside dismissal, auxiliary window mapping, OAuth flows, attachment
and download variants, site menus, screen-reader behavior and all website theme
surfaces remain incompletely verified. A website HTTP 403 is an upstream refusal,
not a reason to bypass security or automatically retry. Theme coverage is partial;
some elevated website surfaces differ from the native palette.

Production resource reduction/freezing is disabled. Small browser settings disable
unused icons, DNS prefetch and hyperlink auditing; no measured CPU/RSS savings are
claimed. Global QtWebEngine infrastructure can remain until the shared host exits.

## Disable and recovery

Use the host's supported plugin disable route:

```sh
omarchy plugin disable slovn.chatgpt-lite
```

Disable destroys owned browser views and linked windows but does not delete the
persistent profile. Backups are independent copies under the user's local data
root. Do not remove profiles or terminate the compositor to recover an update.
Shared-host restart affects other plugins; inspect their active work first.

## License and provenance

No open-source license has yet been selected for this project's own code;
publication alone grants no additional reuse license. Third-party Qt, Chromium,
Quickshell and Omarchy retain their respective licenses. No third-party binaries,
website assets, account images or profiles are distributed. The small Quickshell
patch is provided against its upstream source and is subject to the upstream
license. This is not an official OpenAI or Omarchy product.
