# Engine-selection handoff

## Current goal: speed first

The current user request replaces the former 400 MiB acceptance ceiling and
threefold-memory-reduction direction with responsiveness as the priority.
RAM remains diagnostic information, not a numerical acceptance gate.

Use the original ChatGPT website in the existing Omarchy QML integration.
QtWebEngine/Chromium is the baseline for the speed-first work; this is not a claim
that the installed plugin has switched engines or passed full acceptance.
The earlier cleanup pause below describes its historical checkpoint, not this
current investigation.

Measure cold startup to correct usable content, process restart with persistent
cache, reopening the same retained browser, page Reload and interaction latency
separately. Preserve response bodies, authentication and ordinary website
functionality. An empty/error page or a different workload cannot count as faster.
Browser responsiveness and server-side answer-generation speed are different
measurements. Saved-answer tests do not establish fresh-inference performance.

## Candidates

**Chromium:** active speed-first baseline, using normal execution settings rather
than speculative low-memory flags. The existing service keeps the browser alive
when the panel closes, and the Qt profile has persistent storage/cache paths.
An authenticated VM comparison of `optimize-for-size` gave no material consistent
RAM improvement; it did not establish a speed benefit. A short/long saved chat
passed Reload, while a separate five-response chat showed rendering failures in
both default and size-flag configurations. The exact cause remains unresolved.

**WPE WebKit:** integrated native adapter. The historical trial missed the former
memory target; that alone is no longer an exclusion under the new goal. Complete
website functionality and a current speed advantage have not been demonstrated.

**Servo:** an unoptimized local v0.7.0 experiment with native frame/input transport,
Reload, owned-engine Restart and periodic cookie checkpoints. User reports include
severe slowness, approximately 1 GiB at login, repeated login and an overlapping
left page strip after Reload. No complete repair or working-chat acceptance.
Related/OAuth windows, files, clipboard and composition are incomplete. Synthetic
checks do not establish actual login retention or site fidelity.

**Ladybird:** the source-built VM trial intermittently rendered short/long,
attachment and edited responses. Repeated loading and Reload were not stable.
No complete native-plugin or speed-first acceptance follows from those successes.

**Other probes:** Blitz refused the actual site with HTTP403. Aurora failed to
build; Spiral/Gosub were not usable full-site browsers. These are negative
observations, not a comprehensive ranking.

## Speed-first VM screen

A bounded screen used the actual `Browser.qml`, Qt 6.11.2/Chromium 140,
460×560/DPR 1 and the same saved two-turn conversation. It made no new submissions.
The cold launch did not reach valid conversation readiness within 180 seconds.
A restart with the same persistent profile/cache rendered both responses after
130.8 seconds. Three hide/show cycles retained the document, renderer and complete
responses. Qt frame notification and JavaScript confirmation both arrived within
83–483 ms per cycle. These are not physical input-to-photon measurements or an
installed shared-shell benchmark; the warm cycles have no contemporaneous image.

The subsequent Reload created a new document but failed readiness: the long answer
became a rendering fallback. That failure is retained alongside the warm success.
Keeping an already working page is the supported fast path, not a new improvement
introduced by this documentation change. Cold startup and Reload remain unresolved.

The main document reported tasks of about 30 seconds despite persistent HTTP cache.
A separate CPU profile captured 19,674 samples. React traversal/commit work and
Zod schema initialization appeared among the hot functions; this does not identify
one root cause or a proven repair. Its 64 slightly negative timestamp intervals
are retained, so the offline summary uses sample counts, not CPU-time percentages.
No numerical RAM threshold was used to admit or reject this speed screen.

## Strict site isolation continuation

One subsequent Qt Reload exposed `Timed out waiting for the DIL runner worker`.
The matching public website asset has a 10-second worker-readiness deadline;
it pauses while the document is hidden and rearms with a full budget when visible.
This identifies that occurrence's immediate failure, not why readiness was late.
Large main-thread tasks and the historical failures are not a proven common cause.

A native-window/page-visibility binding was tested and reverted: startup remained
slow and ordinary foreground Reload still failed. Its warm observations did not
establish fresh consumer acceptance. The original `Browser.qml` was restored.

Qt 6.11.2 source defaults strict site isolation off. A sequential comparison used
byte-identical copies of one stopped task-owned profile/cache and the same native
browser, viewport and observers. Ordinary Qt failed both 180-second readiness
windows, with both answers replaced by fallbacks. Adding `--site-per-process`
rendered the exact short and long responses in 97.5 seconds and Reload in 41.6.
A separate bounded confirmation passed at 118.0 seconds, then two actual Reloads
at 68.7 and 109.8 seconds. The repository startup wrapper subsequently passed
another cached start at 101.3 seconds. No new model submissions were made.

Iframe debugging targets appeared during the isolated task phases. Child-domain
observer requests also timed out, so exact DIL frame/process placement and the
worker-delay cause remain unconfirmed. Sequential server/VM/cache effects prevent
a precise speedup ratio. Six successful saved-response phases are useful bounded
mitigation evidence, not a stable distribution or permanent repair guarantee.

Four retained-page cycles passed renderer/document/content/freshness checks.
Qt frame notifications took 41–253 ms; fresh JavaScript acknowledgments took
77–169 ms. These are not physical input-to-photon or complete-first-frame timings.
Native post-warm images are separate evidence. Wayland keyboard input after
controlled DOM focus entered a test draft, preserved it across hiding/reopening,
and cleared only that unchanged draft. Full shared-shell input routing, fresh
inference, many-turn history, voice and current workstation GPU remain unverified.

The current inert Content/Browser preview rendered with contained geometry, but
strict offscreen diagnostics failed on Vulkan/GPU warnings. The original native
browser test baseline also remains red; targeted checks do not replace that gate.

## Shared-shell continuation

The actual Omarchy shell in VM107 loaded the assembled plugin with the corrected
engine selector and a compatible 0.3.1 host. The popover was 460×560/DPR1; its
original-site viewport was 456×484 because the native header and border reserve
space. One saved-task start and native IPC Reload passed exact response admission
in 151.2 and 157.7 seconds. Two further starts passed at 71.9 and 125.8 seconds.
Native images show the actual header and response body, not a full first-frame
proof. This different geometry/workload cannot yield a standalone speedup ratio.

The shared-shell campaign retained failures: incorrect engine selection before
the null fix, two shell-IPC startup-selection failures, missed pointer coordination,
and a Wayland `wtype` timeout. A timely QEMU click did focus the unique empty
editor, but typing, draft retention and cleanup did not pass in the shared shell.
The final two starts failed readiness, including `Page.createIsolatedWorld timeout`
and a still-loading page. Correct route/composer with no response blocks was not
admitted. Strict isolation is therefore not an accepted stable shared-shell fix.

Eight finite replacement-host attempts created five browser instances, five task
navigations and one actual Reload, with zero submissions. This is separate from
the earlier standalone campaign. After every attempt the candidate host stopped,
the original shell.json bytes were restored and the test plugin was unloaded.
The task-owned profile/cache and any possible partial draft were retained privately.
The VM's ordinary shell was restored and responded to PID-specific IPC.
No workaround bypassed the host guard or weakened site protections.

## Chromium startup policy

`native/chromium-env.sh HOST [ARGUMENT ...]` is an opt-in startup prefix for the
existing managed compatible host. It sets `CHATGPT_LITE_ENGINE=chromium`, appends
`--site-per-process` to existing QtWebEngine flags and `exec`s the supplied argv.
The source service selects Chromium for that opt-in; an explicit nonempty Servo
socket still takes precedence and the default WPE path is unchanged. The shared
VM consumer exposed a selector defect: `Quickshell.env` returns null when unset,
so comparing it directly with an empty string incorrectly selected Servo. The
binding now normalizes an absent socket to empty; null and empty cases are covered
by the startup-policy regression. Engine-scoped
profiles are retained; the wrapper performs no authentication migration.

The wrapper adds no debugger, sandbox exception, website patch, service or
background process. The caller retains host selection and single-owner lifecycle.
It was executed by the VM browser consumer with observed process environment,
correct content, native typing and retained-draft checks. Its argv/environment
and source engine selection are covered by `node tests/performance-goal.mjs`.
It does not build a compatible host or assemble/install the plugin. Installing
source files alone would not change an already-running Chromium process.

## Saved source and local state

The pre-cleanup checkpoint is `0bb0a410255bda7117d9377e22f745b1aa464b75`.
The [Servo archive](../engines/servo/README.md) includes the complete 12-file diff
against pinned upstream and the modified gaol source. It does not include the
multi-gigabyte build tree, engine executable or private profile.

The installed local plugin's service entry point is
`~/.config/omarchy/plugins/slovn.chatgpt-lite/servo-candidate-08/ServoService.qml`.
Source `manifest.json` still points to `native/Service.qml`; these are not
identical installations. Fresh read-only IPC still reports hidden
`SERVO_EXPERIMENTAL` with `host_compatible: false`. In the installed service that
field comes from `Qt.application.arguments.length > 0`, not the disk identity
file: the running service's argument-readiness guard is not satisfied. Selecting
Chromium in that host would be refused by the existing guard. Its patched-host
identity also predates the installed Quickshell/Qt versions; that separate fact
does not identify the loaded binary's exact defect or prove a replacement host
compatible. This is unrelated to the retired memory target.
VM browser-component checks do not establish installed shared-shell acceptance.
The source startup policy has not been installed in the workstation host, the
running engine has not switched, and no workstation test window was opened.
A pinned Quickshell 0.3.2 host with the argv0 patch was built against the current
workstation Qt packages. Its inert offscreen consumer reported argc1 and a ready
off-record profile, then stopped normally. Full production-shell/GPU compatibility
is not established by that check. The patch now applies to both 0.3.1 and 0.3.2.

The original local Servo workspace is
`~/.local/share/chatgpt-servo-repair-Ar9ArjX8`. It remains untouched for recovery.
Private historical reports and generated checkout outputs were moved to
`~/.hygiene/omarchy-chatgpt-lite/save-clean-20261009/local-archive/`.

## Historical cleanup checkpoint

The save-and-clean checkpoint `f92d74210f48b909d0fd91a060701a4fde029738` paused
engine development, builds and tests for that earlier operation. This describes
its historical scope, not the current speed-first request. Existing guards and
test sources remain preserved. The subsequent VM continuation and startup policy
do not establish full installed-plugin or release acceptance. Publication is a
source checkpoint, not an engine deployment or proof of responsiveness.
