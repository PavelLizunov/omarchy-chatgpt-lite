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

## Saved source and local state

The pre-cleanup checkpoint is `0bb0a410255bda7117d9377e22f745b1aa464b75`.
The [Servo archive](../engines/servo/README.md) includes the complete 12-file diff
against pinned upstream and the modified gaol source. It does not include the
multi-gigabyte build tree, engine executable or private profile.

The installed local plugin uses `servo-candidate-08/ServoService.qml`. Source
`manifest.json` still points to `native/Service.qml`; these are not identical
installations. The installed service was observed as hidden
`SERVO_EXPERIMENTAL` with `host_compatible: false`. Its recorded patched-host
identity predates the installed Quickshell/Qt versions. Compatibility with the
current host is unverified; that flag alone does not prove the old Qt argument
bug still exists. This is separate from the retired memory target.
VM browser-component checks do not establish installed shared-shell acceptance. This documentation update does not
switch the running engine.

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
