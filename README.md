# Termode

Termode is a standalone Android terminal project with a REAL PTY shell,
script packages, workspace folders, and beta QA tooling.

Current status: v0.38 Documentation / Onboarding Polish.

Termode is not a full Linux distribution and is not a Termux replacement yet.
It is a focused terminal app that proves a shell-first mobile workflow while
keeping runtime scope honest and testable.

## What Works Today

- REAL PTY shell sessions
- shell-first command entry with host command interception
- script packages through `pkg`
- trusted remote script package repo flow
- workspace folders under Termode app storage
- host file commands such as `host-write`, `host-cat`, and `host-ls`
- Android storage bridge when the user links a folder
- sessions, tabs, history, and scrollback persistence
- keyboard, ANSI, paste, copy, and scrollback helpers
- localhost/preview diagnostics
- built-in JNI native tools
- `js-proof` controlled evaluator
- beta QA commands and doctors

## Not Included Yet

- Node.js or npm
- Python
- Git
- full Linux package manager
- native binary package installs
- full Termux compatibility

QuickJS and Duktape remain probe surfaces only. Runtime direction is frozen
while Termode stabilizes the product experience.

## Start Here

```sh
welcome
examples
glossary
commands
doctor
qa-status
```

Try the first shell/package flow:

```sh
default-shell
pwd
pkg list
pkg install hello
hello
```

## Package Basics

Packages are script packages managed by Termode:

```sh
pkg list
pkg install hello
hello
pkg verify hello
pkg remove hello
pkg doctor
```

Native binary packages are not supported.

## Workspace Basics

Workspaces are project folders under Termode app storage:

```sh
workspace-init demo
workspace-cd demo
host-write hello.txt "hello"
host-cat hello.txt
workspace-doctor
```

## QA Status

Run:

```sh
qa-status
doctor
beta-score
```

`READY WITH LIMITATIONS` is expected when limitations are known and documented,
for example frozen runtime work or unlinked Android storage.

## Runtime Freeze

Termode is stabilizing the current app before adding larger runtime systems.
Node/npm/Python/Git and native package managers are future work, not current
features.

See [docs/RUNTIME_DECISION_FREEZE.md](docs/RUNTIME_DECISION_FREEZE.md).

## Screenshots

Screenshots are not checked into the repository yet. Add beta screenshots here
after the UI polish pass.

## Roadmap

- v0.38 Documentation / Onboarding Polish
- v0.39 UI Polish / Settings Polish
- v0.40 Beta Candidate
- Node/npm later, after product stability

## Docs

- [Getting Started](docs/GETTING_STARTED.md)
- [Known Limitations](docs/KNOWN_LIMITATIONS.md)
- [Roadmap](docs/ROADMAP.md)
- [Command Guide](docs/COMMAND_GUIDE.md)
- [Beta Readiness](docs/BETA_READINESS.md)
- [Device QA Bug Bash](docs/DEVICE_QA_BUG_BASH.md)
