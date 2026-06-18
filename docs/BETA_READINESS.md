# Termode v0.36 Beta Readiness

v0.36 is a product stabilization pass. It does not add new runtimes. It makes
Termode easier to understand, diagnose, and test as a standalone Android
terminal.

## Supported Today

- REAL PTY shell-first terminal
- script packages through `/system/bin/sh`
- trusted remote script package repository flow
- workspace folders under Termode app storage
- Android storage bridge where linked by the user
- sessions, tabs, history, and scrollback persistence
- terminal UX helpers for keyboard, paste, ANSI, copy, and scrollback
- localhost/preview diagnostics
- built-in JNI native tools
- `js-proof` controlled evaluator
- frozen runtime decision via `runtime-freeze`

## Known Limits

- No Node.js, npm, Python, or Git.
- Native binary packages are not supported.
- QuickJS and Duktape are probe surfaces only.
- Direct app-bin execution may be blocked by Android.
- Storage import/export may be limited by Android storage permissions.
- Some terminal apps/features may not behave exactly like desktop Linux.
- This is beta software.

## Deferred

- QuickJS integration
- Duktape integration
- Node.js
- npm
- Python
- Git
- native binary package installs
- native package manager

## Readiness Criteria

Termode is beta-ready when these checks are consistently healthy or clearly
limited on device:

- `doctor`
- `beta-status`
- `pkg doctor`
- `workspace-doctor`
- `session-doctor`
- `runtime-freeze doctor`
- `preview-doctor`
- `localhost-doctor`
- `native-tool doctor`
- `js-proof doctor`

Use `beta-checklist` and `qa-checklist` for the manual pass.

v0.37 adds `qa-run`, `qa-status`, `qa-report`, and `qa-reset` for the device
bug-bash pass. See [DEVICE_QA_BUG_BASH.md](DEVICE_QA_BUG_BASH.md).

v0.37.1 keeps the runtime decision frozen and focuses on QA rough edges:

- `qa-status` reports `READY WITH LIMITATIONS` when only accepted LIMITED
  statuses are present
- `host-rm` can remove empty workspace directories created by `host-mkdir`
- protected Termode roots remain blocked from host file deletion
- host file commands reject explicit `..` parent traversal
- unified doctor recognizes package `Status: HEALTHY`
- `runtime-freeze doctor` works inside the installed APK using the embedded
  freeze decision when repo markdown files are unavailable

v0.38 focuses on documentation and onboarding:

- `welcome`, `getting-started`, and `first-run` are compact first-run guides
- `examples` provides copy-friendly command examples by category
- `glossary` explains beginner terms
- `onboarding-doctor` checks onboarding/docs readiness
- README and docs now point new beta testers to the same starting flow
- the startup banner now reports `Termode v0.38` and points to onboarding
  commands

Known v0.38 QA limitation:

- automated `adb input text` was unreliable on the test device, so full manual
  command entry remains a hand checklist item

v0.39 focuses on UI and settings polish (no new runtimes):

- `settings-summary` now lists theme, font size, line height, cursor, blink,
  scrollback, paste limits, keep-screen-on, and welcome banner
- `settings-doctor` adds font-size and line-height health checks
- `settings-reset-safe --confirm` restores visual/terminal defaults without
  touching packages, workspaces, sessions, history, repo config, or files
- `theme-test` prints a readability sample (normal/dim/bold/ANSI/badges)
- `status` prints a compact mode/shell/session/workspace/packages/runtime/beta
  summary
- the settings screen exposes line height, scrollback, ANSI debug, keep screen
  on, a safe visual reset, and the correct app version
- the startup banner now reports `Termode v0.39`
- tab name/badge wrapping and prompt/keyboard spacing were tightened

The runtime decision remains frozen. Node.js, npm, Python, Git, QuickJS, and
Duktape are still not added.
