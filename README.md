# Termode

Termode is an Android terminal app built around a REAL PTY shell-first
experience, script packages, workspace tools, and compact diagnostics.

Current status: v0.37 Device QA Bug Bash.

## Supported

- REAL PTY shell sessions
- script packages through `/system/bin/sh`
- remote script package trust/source locking
- workspace folders and host file commands
- storage bridge where the user links a folder
- sessions, tabs, history, and scrollback persistence
- terminal UX helpers for keyboard, ANSI, paste, copy, and scrollback
- built-in JNI native tools
- `js-proof` controlled evaluator
- localhost/preview diagnostics

## Runtime Decision

Runtime direction is frozen. Termode does not currently include Node.js, npm,
Python, Git, QuickJS, Duktape, native binary packages, or a native package
manager. QuickJS and Duktape remain probe command surfaces only.

See [docs/RUNTIME_DECISION_FREEZE.md](docs/RUNTIME_DECISION_FREEZE.md).

## Useful Commands

- `welcome`
- `commands`
- `doctor`
- `beta-status`
- `qa-run`
- `qa-status`
- `pkg help`
- `workspace`
- `runtime-freeze status`

See [docs/COMMAND_GUIDE.md](docs/COMMAND_GUIDE.md) and
[docs/BETA_READINESS.md](docs/BETA_READINESS.md).
