# Termode Command Guide

Use `welcome`, `examples`, and `glossary` first if you are new.

## Getting Started

- `welcome`
- `getting-started`
- `first-run`
- `examples`
- `examples <category>`
- `glossary`
- `commands`
- `commands --all`
- `help`

## Shell / PTY

- `default-shell`
- `stop-shell`
- `normal-mode`
- `mode`
- `reload-helpers`

## Sessions / Tabs

- `tabs`
- `tab-new`
- `tab-switch <number>`
- `tab-rename <name>`
- `tab-close`
- `session-info`
- `session-doctor`
- `history`

## Packages

- `pkg help`
- `pkg list`
- `pkg install <name>`
- `pkg verify <name>`
- `pkg remove <name>`
- `pkg repair`
- `pkg doctor`

## Workspace / Files

- `workspace`
- `workspace-init <name>`
- `workspace-cd <name>`
- `workspace-doctor`
- `host-ls`
- `host-cat <file>`
- `host-write <file> <text>`
- `host-touch <file>`
- `host-mkdir <dir>`
- `host-rm <path>`

## Storage

- `storage-status`
- `storage-link`
- `storage-list`
- `storage-read <file>`
- `storage-write <file> <text>`
- `storage-test`
- `storage-help`

## Terminal UX

- `keyboard-help`
- `keyboard-test`
- `keyboard-settings`
- `terminal-settings`
- `ansi-test`
- `input-test`
- `resize-info`
- `scroll-test <lines>`
- `copy-last`
- `copy-session <lines>`
- `paste-force`

## Settings / Theme / Status

- `settings-summary`
- `settings-doctor`
- `settings-reset-safe --confirm`
- `theme-test`
- `status`

## Beta Candidate / Feedback / RC

- `build-info`
- `beta-candidate` (`status`, `checklist`, `notes`, `limits`, `ready`)
- `feedback` (`template`, `checklist`)
- `rc-checklist`
- `rc-status`

`feedback` and the `rc-*` commands are local only — no network upload. `rc-status`
reports `RC CLEANUP READY` when core systems are healthy; the intentional frozen
runtime and unlinked storage do not block it.

## Runtime Environment

These describe Termode's prefix, PATH overlay, environment, bin discovery, and
future runtime/toolchain layer. They do not install, download, or execute
external runtimes yet. See
[Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md) and
[Runtime Expansion Architecture](RUNTIME_EXPANSION_ARCHITECTURE.md).

Prefix / environment:

- `prefix-info`
- `prefix-init`
- `prefix-status`
- `prefix-doctor`
- `path-info`
- `path-status`
- `path-preview`
- `path-doctor`
- `env-info`
- `env-status`
- `env-preview`
- `env-doctor`
- `env-check`
- `env-script`
- `bin-list`
- `bin-which <command>`
- `bin-doctor`
- `shim-info`
- `shim-list`
- `shim-doctor`

Toolchains (planned):

- `toolchain-status`
- `toolchain-list`
- `toolchain-info <name>`
- `toolchain-plan`
- `toolchain-doctor`

Install planning:

- `runtime-install` (`list`, `plan <tool>`, `status`, `doctor`)

Guided presets (planned):

- `dev-setup` (`list`, `plan <preset>`)
- `dev-doctor`

`prefix-init` is idempotent and never deletes user files. Toolchain/runtime/dev
doctors report `ARCHITECTURE PHASE` for planned-but-missing tools — that is
expected, not a failure.

`settings-reset-safe` restores visual/terminal settings to defaults and
requires `--confirm`. It keeps packages, workspaces, sessions, history, repo
config, and files. See [UI & Settings](UI_SETTINGS.md).

## Preview / Localhost

- `preview`
- `preview-url <port>`
- `preview-copy <port>`
- `preview-open <port>`
- `preview-check <port>`
- `preview-history`
- `preview-doctor`
- `localhost-doctor`
- `port-check <port>`
- `http-test <url-or-port>`

## Runtime Status

- `runtime-freeze status`
- `runtime-freeze decision`
- `runtime-freeze deferred`
- `runtime-freeze why`
- `runtime-freeze next`
- `runtime-freeze doctor`
- `runtime-doctor`
- `native-tool doctor`
- `js-proof doctor`

QuickJS and Duktape are probe surfaces only. Node.js, npm, Python, and Git are
not included yet.

## QA / Beta

- `doctor`
- `doctor --verbose`
- `qa-status`
- `qa-run`
- `qa-report`
- `qa-reset`
- `beta-status`
- `beta-score`
- `beta-known-limits`
- `onboarding-doctor`

## Advanced Probes

- `runtime-candidates`
- `runtime-candidate <name>`
- `runtime-decision`
- `runtime-risks`
- `runtime-next`
- `js-engine-decision`
- `quickjs doctor`
- `duktape doctor`
