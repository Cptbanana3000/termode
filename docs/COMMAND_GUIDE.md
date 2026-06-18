# Termode Command Guide

## Start Here

- `welcome`
- `commands`
- `doctor`
- `beta-status`
- `help`

## Shell

- `default-shell`
- `stop-shell`
- `mode`
- `reload-helpers`

## Packages

- `pkg help`
- `pkg list`
- `pkg install <name>`
- `pkg remove <name>`
- `pkg doctor`

## Workspace And Files

- `workspace`
- `workspace-init <name>`
- `workspace-cd <name>`
- `workspace-doctor`
- `host-ls`
- `host-cat <file>`
- `host-write <file> <text>`

## Diagnostics

- `doctor`
- `doctor --verbose`
- `beta-doctor`
- `settings-doctor`
- `bug-report`

## Runtime

- `runtime-freeze status`
- `runtime-freeze decision`
- `native-tool doctor`
- `js-proof doctor`
- `quickjs doctor`
- `duktape doctor`

QuickJS and Duktape are probe surfaces only. Node.js and npm are not included.

## Preview And Localhost

- `preview`
- `preview-url <port>`
- `preview-doctor`
- `localhost-doctor`
- `port-check <port>`
- `http-test <url>`

## Beta QA

- `beta-score`
- `beta-checklist`
- `beta-known-limits`
- `qa-checklist`
- `qa-run`
- `qa-status`
- `qa-report`
- `qa-reset`
