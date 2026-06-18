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
