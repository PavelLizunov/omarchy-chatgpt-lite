# ChatGPT Lite for Omarchy

Original [ChatGPT](https://chatgpt.com) in a native QML top-bar popover using
experimental embedded web-engine surfaces. The default source entry still uses
WPE WebKit. A local Servo v0.7.0 fork is now installed as an explicit trial through
the same native Service; it is not a packaged release or an accepted memory solution.
Chromium remains only for historical tests and preserved data, not the requested
replacement. No Python plugin runtime, API client or replacement chat UI.

**Experimental source, not a production-ready release or Marketplace submission.**
A compatible Omarchy host is required; review the host and installation boundaries.

## Servo trial status

The installed local trial displays original Servo frames in the existing Omarchy
popover and forwards native input. The anonymous ChatGPT document loads, and the
actual Service consumer receives frames. Inert draft/action, viewport sizing,
warm hide/reopen, private transport validation, connected teardown and isolated
cookie/localStorage recreation checks passed. These are not authenticated chat,
physical input, accessibility or visual-fidelity acceptance.

Servo related/OAuth windows, files/downloads, confirmed clipboard exchange and
full composition are not complete. FRAME_READY means received pixels, not website
load success. The header now reports summed Servo executable RSS/CPU from its
exact owned service cgroup, including renamed sandbox processes, rather than
claiming one renderer's memory. User testing reached approximately 998 MiB RSS.
A later three-snapshot inspection reached 1035 MiB RSS / 761 MiB PSS. Intermediate
sandbox fork children were stuck after libc exit handlers; using `_exit` eliminates
them in the isolated regression and loaded candidate. A subsequent installed
snapshot still used about 804 MiB RSS / 601 MiB PSS. These are different workloads,
not a controlled reduction or leak diagnosis. The 200 MiB / threefold working-chat
goal is not established. User testing also reported severe slowness and about1GiB
at login; a later hidden-page sample cannot settle that workload. The loaded engine
is still an unoptimized debug build. Two bounded release-build sessions ended at
their deadlines without a completed executable; no speedup is established.
Swap and shared pages require separate accounting. The full acceptance gate
requires real working-chat responsiveness and counts swapped memory; inert input
timing or low RSS after swapping cannot satisfy it.
The original page was not captured. Shared-shell memory is separate.

The task-local engine retains native multiprocess/seccomp protection with a narrow
compatibility fork. Eleven targeted sandbox checks passed; enlarged syscall
admission is not independently certified. It uses a separate private profile;
Chromium/WPE cookies are not migrated. The local candidate has separate Reload page and Restart engine controls.
Reload retains the engine/profile; Restart replaces only the exact owned
`chatgpt-servo-engine.service` and reconnects using the same profile. Both actions
can lose unsent text. The persistent user unit has no automatic restart loop or
boot enablement; the plugin starts it on demand. Disable stops the owned engine;
hiding retains it warm. Public cookies are checkpointed atomically every two
seconds when changed, with private directories and 0600 files. The private jar
never overwrites the public jar. An isolated forced-crash/recreation check
retained persistent, session and HttpOnly cookies plus localStorage. The last
two seconds can still be lost on abrupt termination. Actual ChatGPT login
retention and server-side session expiration remain unverified.

The loaded local recovery candidate is `servo-candidate-08/ServoService.qml`.
The original-site installed consumer received frames without capture/account
actions; the real IPC restart replaced a deliberately stopped engine process set
while retaining the shared shell. This does not establish authenticated chat
functionality, performance or physical button input.

`make servo-probe` builds transport and metrics modules. `make servo-check` exercises
the bounded parser, input routing and connected destruction; `make servo-metrics-check`
uses a finite owned user service to check exact cgroup/executable/UID admission,
CPU baselines, missing/wrong identities and stale-value clearing. Module build
outputs are not an installation: the QML entry expects local `servo-module` and
`servo-metrics-module` directories with the matching plugin and qmldir. The full Servo fork,
engine build and launch evidence remain outside this repository. Do not infer a
reproducible browser package or production readiness from this module alone.

## Interface

The right-section chat-bubble widget opens a 460 × 560 logical-unit popup.
Outlined Expand/Compact controls resize the same browser without navigation.
Three experimental header layouts are available through the layout icon; the
palette icon cycles Desktop, Light, Dark and Forest without changing the desktop.
The header uses original outline SVG artwork rather than icon-font glyphs.

Resource values update every two seconds only while the main window is open.
WPE page renderers report native process identity through a fixed local extension.
Namespace IDs are resolved to host PIDs and checked as owned descendants. Identity
is refreshed after navigation; duplicate renderer PIDs count once. Their summed
RSS is resident memory, not unique memory or the entire engine footprint. GPU/network/service
processes are excluded from WPE page metrics. WPE shows page-renderer metrics;
Servo instead shows engine metrics as described below. Shared-shell diagnostics
remain separate in IPC status, not attributed to this plugin.
For the Servo trial, the header is explicitly labeled `Servo engine`. Only
processes in the exact configured user-service cgroup with the checked executable
inode count; transport/network helpers and the shared shell do not. Summed RSS can
double-count shared mappings and is not unique allocation, PSS or a savings claim.
CPU 100% means one fully used core. Initial CPU sampling shows an
ellipsis; missing/replaced processes show unavailable, never invented zero usage.
These measurements do not establish optimization savings. The requested 200 MiB
open-page target is not met. The installed WPE candidate's original-site renderer
reached approximately 873 MiB RSS during a bounded load observation. Another WPE
renderer and network process were present, while shared-shell memory remained
separate. These are not matched authenticated Chromium/WPE workload measurements;
no threefold reduction is established. No hard memory cap or automatic page
discard is enabled.

The bounded layer surface uses on-demand keyboard focus, not an xdg-popup grab,
so temporary dictation focus handoffs do not automatically dismiss it. Hide it
with Close or the bar trigger; clicking elsewhere leaves it open. Compositor-level
Voxtype paste/focus integration remains pending user verification.
Hide/reopen keeps one warm primary browser and persistent profile. The WPE path supports up to three
linked windows that share that profile but have independent visibility. A visible
linked window can create another even while the main popover is hidden.

Native framing uses Omarchy Color/Style/Border. Palettes affect only native chrome.
The website controls its own appearance; no CSS or user scripts are injected. Native loading/error feedback occupies a strip
outside the website and collapses after success. Site-owned menus remain original;
The Chromium fallback suppresses generic browser context-menu chrome.

## Requirements and safety

Observed host: Omarchy 4.0.4, Quickshell 0.3.1, Qt 6.11.2, WPE WebKit 2.52.6,
libwpe 1.16.3 and wpebackend-fdo 1.16.1. QtWebEngine remains a fallback dependency.
Imports: QtQuick, QtQuick.Dialogs, QtWebEngine, Quickshell, Quickshell.Io and
installed qs.Commons/qs.Ui. Building the one-shot profile helper needs a C++17
compiler and Make. Tests additionally need Node.js and Qt Quick Test.

The plugin runs unsandboxed as the user inside the existing shared shell. Do not
start a second shell. The browser contacts ChatGPT and its providers normally;
no credentials, API key, security bypass, protocol interception or automatic
challenge retry is added. Persistent profiles are not distributed.

Some Quickshell hosts discard argv[0], which QtWebEngine requires. The Chromium fallback rejects
such hosts with HOST_ARGUMENTS_EMPTY before opening a profile. The separately
built development host uses native/host-argv.patch with a guarded managed service.
This repository ships no host binary, automatic host build, systemd unit or
identity file. native/launch-host.sh verifies expected package versions and hashes
using Bash, jq, pacman and sha256sum, then starts the existing managed unit or
falls back to the stock launcher. Stock incompatibility is not silently bypassed.

## Build and installation boundary

```sh
make
make check
make wpe-probe
make wpe-check
```

`make` creates build/prepare-profile. This native one-shot helper walks directories
with openat/O_NOFOLLOW, rejects relative and symlink paths, checks owned profile
children and enforces mode0700 without reading cookies or page data. Service runs
it through one owned Process with a five-second timeout. Profile and cache remain
under `${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-chatgpt-lite-qt/profile` and
`${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-chatgpt-lite-qt/cache`.

WPE uses separate owned mode-0700 directories under
`${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-chatgpt-lite-wpe/profile` and
`${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-chatgpt-lite-wpe/cache`. Cookies are stored
by WebKit; no Chromium cookies are imported. A new login may be necessary.
The WPE path admits absolute, non-symlink private directories before session creation.

For a reviewed independent installation, copy build/wpe into native/wpe-module,
including its qmldir and extensions directory. The extension reads process identity
only, not page content. Rebuild it with the QML plugin after incompatible upgrades.
The native/wpe/Browser.qml and native/WpeContent.qml files belong to this candidate.

For a reviewed independent installation, the native/ QML/JS files and compiled
build/prepare-profile and build/resource-module belong together in the installed native/ directory with
manifest.json at the package root. The helper must be executable; resource-module must be copied into native/ and
rebuilt after incompatible Qt upgrades. Source saves do
not deploy the installed copy. No automatic installer is supplied: reconcile
existing local changes, stage outside the recursively watched plugin tree, preserve
a restorable snapshot and use the supported host lifecycle. Shared-shell reloads
can affect other plugins and active drafts/jobs. Never mirror-delete user data.
The preserved legacy GTK/WebKit implementation and its installers are no longer
part of this working tree; previous source is available in Git history.

The WPE/Chromium paths require native confirmation for clipboard reads and a
user-chosen download path. These interfaces are not yet implemented for Servo.
Disable releases owned views, not persistent profile data:

```sh
omarchy plugin disable slovn.chatgpt-lite
```

## Isolated memory experiments

The optional native probe loads the actual Browser offscreen with an ephemeral
profile, never the production shell/profile. Build once, then run a finite matrix
in separate managed user cgroups without restarting the desktop:

```sh
make memory-probe
node tests/memory-probe.mjs "$HOME/.local/share/chatgpt-memory-new-evidence" synthetic
# Explicit anonymous original-site loading, no account input or script filters:
node tests/memory-probe.mjs "$HOME/.local/share/chatgpt-memory-new-live-evidence" live
```

Each case has an 18-second lifetime, fixed memory cap, disabled swap and core
dumps, and a unique recorded unit. Synthetic cases compare optional/core script
exclusion with negative functional controls. Live mode tests only anonymous page
loading at 1 GiB and 200 MiB, not authenticated features or visual acceptance.
No production resource filter or hard cap is applied. The production candidate now
uses WPE; this Chromium probe retains its original explicitly separate scope. It
records in-process cgroup limits/current/peak/events separately from renderer RSS;
shared mappings and cache accounting make these different quantities. A successful
load with a broken action, or an out-of-memory kill, is not an optimization.

## Verification limits

Native profile checks cover private modes, idempotence, legacy-data preservation,
XDG paths and rejection of symlinks/non-directories/relative paths. Qt tests cover
inert input/draft retention, settings and error-strip restoration.

The actual QML bar fixture checks pointer/keyboard Expand/Compact and auxiliary
ownership/admission using off-record HTML. It requires the optional static preview
adapter from [qml-preview-mcp](https://github.com/PavelLizunov/qml-preview-mcp).
Synthetic HTML is a component test, not original-site design evidence. The
separate MCP tool currently uses Python; it is development tooling, not this
plugin's runtime. That independent repository is not migrated by this project.

The WPE candidate does not support the existing primary-page capture bridge.
The opt-in native/Capture.qml Chromium bridge is disabled by default and built separately
from qml-preview-mcp. It captures only an already loaded primary browser with
explicit image consent; it cannot click menus or capture auxiliaries/native chrome.
A genuine hidden ChatGPT page was captured and inspected in the development host.
Full original-site functionality, physical focus/Escape/dismissal, auxiliary mapping,
OAuth, attachments, downloads, all theme surfaces and accessibility remain
incompletely verified. HTTP403 is an upstream refusal, not permission to bypass
security. Production freezing/resource reduction stays disabled; no CPU/RSS savings
are claimed. Shared Chromium infrastructure can outlive fallback plugin disable.

WPE candidate acceptance is deliberately limited: inert pointer/key/text-commit,
copy, warm retention, Expand/Compact, related-view ownership and persistent-cookie
checks passed. Installed-consumer rendering and geometry passed. File/save/paste
dialog wiring exists, but original-site upload/download/clipboard/OAuth/streaming
and accessibility are not fully verified. An initial live candidate crashed in
WebKit's render-failure path. The adapter now reports render errors and avoids
reentrant buffer acknowledgements; bounded subsequent observation is not proof
that all crashes are eliminated. This version is for explicit user testing.

## License

No open-source license has been selected for this project's own code; publication
alone grants no additional reuse license. Qt/Chromium/Quickshell/Omarchy retain
their respective licenses; no third-party binary, website asset, account image or
profile is included. The small upstream Quickshell patch follows its upstream
license. This is not an official OpenAI or Omarchy product.
