# ChatGPT Lite for Omarchy

Experimental native QML popover for the **original ChatGPT website** inside the
existing Omarchy shell. This is a research checkpoint, not a working release.
**An embedded engine has not been selected.**

## Current state

- Chromium is retained as historical source, not the intended solution.
- WPE WebKit did not meet the memory goal.
- Servo is an incomplete local experiment. It has not met the responsiveness,
  memory, authentication or full website-functionality requirements.
- The reported overlapping page strip after Reload remains unresolved.
- The target remains a usable working chat with roughly threefold lower memory,
  toward 200 MiB. No candidate has demonstrated it.

See [engine status](docs/engine-status.md) for the handoff.

## Source layout

- `native/`: shared QML UI, engine adapters, C++ helpers and lifecycle scripts.
- `engines/servo/`: pinned upstream patch, modified gaol source and original
  development launcher. See its [snapshot guide](engines/servo/README.md).
- `tests/`: existing historical checks and fixtures. Retained for recovery;
  this cleanup does not run or extend them.
- `Makefile`: helper and module build targets. No complete browser installer.
- `manifest.json`: experimental plugin metadata. The source entry defaults to
  WPE; the installed local Servo trial is a separate copy.

## Development boundary

Source checkout:

```text
/home/slovn/Work/omarchy-plugins/omarchy-chatgpt-lite
```

Omarchy loads an independent installed copy under
`~/.config/omarchy/plugins/slovn.chatgpt-lite`. Saving or pushing source does not
update the running plugin. This cleanup does not deploy, restart services,
change profiles, run builds or choose an engine.

The experiment uses Omarchy 4.0.4, Quickshell 0.3.1 and Qt 6.11.2. The local
host and Servo runtime are not portable packages. Do not treat archived launchers
or unit examples as installation instructions. Native integration keeps the
website original; no API client or replacement chat UI is intended.

## Recovery checkpoint

The pre-cleanup source is saved in commit
`0bb0a410255bda7117d9377e22f745b1aa464b75`, including the Servo patch and gaol fork.
Recover an earlier file with `git show <commit>:<path>`. Local reports and compiled
outputs are preserved outside the checkout, not published as source.

## License

No open-source license has been selected for this project's own code. Publication
alone does not grant a reuse license. Third-party licenses are preserved with
archived engine sources. Browser profiles, credentials, account images and
compiled engine binaries are not distributed. This is not an official OpenAI
or Omarchy product.
