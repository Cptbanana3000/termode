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

## Runtime Package Prototype

- `runtime-pkg`
- `runtime-pkg help`
- `runtime-pkg list`
- `runtime-pkg available`
- `runtime-pkg info <name>`
- `runtime-pkg install <name>`
- `runtime-pkg remove <name>`
- `runtime-pkg verify <name>`
- `runtime-pkg status`
- `runtime-pkg doctor`
- `runtime-pkg repair`
- `runtime-abi`
- `hello-bin`

`runtime-pkg install hello-bin` installs only the built-in safe prototype
package. It does not install Git, Node.js, npm, Python, or real native binary
packages.

## Git (Feasibility)

- `git-status`
- `git-info`
- `git-plan`
- `git-version`
- `git-doctor`
- `git-test-plan`
- `git` (placeholder; guides you when Git is not installed)

Git is **planned, not installed** in this build. There is no Git artifact, so
`runtime-pkg install git` refuses safely, `git-version` reports it is not
installed, and `bin-which git` does not find it. Termode never fakes Git. See
[Git Support Strategy](GIT_SUPPORT_STRATEGY.md).

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

`feedback` and the `rc-*` commands are local only; no network upload.
`rc-status` reports `RC CLEANUP READY` when core systems are healthy. The
intentional frozen runtime and unlinked storage do not block it.

## Runtime Environment

These describe Termode's prefix, PATH overlay, environment, bin discovery,
runtime package prototype, and future runtime/toolchain layer. They do not
install Git/Node/npm/Python, download from the internet, or execute unknown
external runtimes yet. See
[Binary Package Installer Prototype](BINARY_PACKAGE_INSTALLER_PROTOTYPE.md),
[Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md), and
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

Install planning / prototype status:

- `runtime-install` (`list`, `plan <tool>`, `status`, `doctor`)

Guided presets (planned):

- `dev-setup` (`list`, `plan <preset>`)
- `dev-doctor`

`prefix-init` is idempotent and never deletes user files. Toolchain/runtime
doctors report `PROTOTYPE READY` or intentional `LIMITED` states for
planned-but-missing real tools; that is expected, not a failure.

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
