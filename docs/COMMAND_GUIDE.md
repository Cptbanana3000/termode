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
