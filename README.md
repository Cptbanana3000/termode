# Termode

Termode is a standalone Android terminal project with a REAL PTY shell,
script packages, workspace folders, and beta QA tooling.

Current status: **v0.48 Verified Git Artifact Bundle / Smoke Test** (terminal foundation beta).

Termode is not a full Linux distribution and is not a Termux replacement yet,
and it is not a stable v1.0. It is building a complete standalone Android
terminal/dev environment — easier and more guided than Termux — and only later
integrating into CalypsoIDE.

Termode has a strong terminal foundation today (REAL PTY, packages, workspaces,
sessions, QA/beta tooling). It does **not** yet include Node.js, npm, Git,
Python, compilers, or a full Linux package ecosystem — those are **planned, not
installed**. v0.48 adds project-controlled Git bundle validation,
checksum/file checks, install rollback, and a smoke-test path for `git
--version`. It still ships **no Git artifact**, so Git is reported
`TEMPLATE_ONLY` or `UNAVAILABLE`/not installed and the installer refuses
safely. Termode never fakes Git. See
[Git Artifact Contract](docs/GIT_ARTIFACT_CONTRACT.md),
[Git Artifact Acquisition](docs/GIT_ARTIFACT_ACQUISITION.md),
[Git Build Pipeline](docs/GIT_BUILD_PIPELINE.md),
[Git Bundle Smoke Test](docs/GIT_BUNDLE_SMOKE_TEST.md),
[Git Support Strategy](docs/GIT_SUPPORT_STRATEGY.md),
[Binary Package Installer Prototype](docs/BINARY_PACKAGE_INSTALLER_PROTOTYPE.md),
[Prefix / PATH / Environment](docs/PREFIX_PATH_ENVIRONMENT.md),
[Runtime Expansion Architecture](docs/RUNTIME_EXPANSION_ARCHITECTURE.md),
[Beta Install](docs/BETA_INSTALL.md), and [Beta Testing](docs/BETA_TESTING.md).

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
- settings/theme/status readouts (`settings-summary`, `theme-test`, `status`)
- data-safe visual reset via `settings-reset-safe --confirm`
- safe Termode prefix, PATH overlay, env preview/doctor, and bin discovery
- prototype runtime package installer with `hello-bin`

## Not Included Yet

- Node.js or npm
- Python
- Git
- full Linux package manager
- real native binary package installs
- full Termux compatibility

QuickJS and Duktape remain probe surfaces only. Runtime direction is frozen
while Termode stabilizes the product experience.

## Start Here

```sh
welcome
examples
glossary
commands
status
build-info
beta-candidate status
prefix-status
path-status
env-status
runtime-pkg status
runtime-abi
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

## Install (Beta)

Termode ships as a debug APK for beta testing:

1. Enable "Install unknown apps" for your file manager or browser.
2. Copy `Termode-v0.48-git-bundle-debug.apk` to the device and tap to install.
3. Launch Termode and run `welcome`, then `doctor` and `dev-doctor`.

Full steps and how to clear app data are in
[docs/BETA_INSTALL.md](docs/BETA_INSTALL.md).

## Beta Testing Checklist

```sh
welcome
doctor
rc-status
beta-candidate ready
qa-status
feedback
```

Report issues with `feedback template` plus `bug-report` (which omits private
env vars, tokens, and full paths). See [docs/BETA_TESTING.md](docs/BETA_TESTING.md)
for what to report and which behaviors are expected `LIMITED` versus release
blockers.

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

Runtime package installs are prototype-only. Real native binary packages are
planned, not enabled.

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

## Runtime Environment

Termode is stabilizing the current app before adding larger runtime systems.
Node/npm/Python/Git and native package managers are future work, not current
features.

v0.43 added a safe environment layer for future tools:

```sh
prefix-init
prefix-status
path-preview
env-preview
env-check
bin-list
shim-info
```

REAL PTY shells receive `TERMODE_HOME`, `TERMODE_PREFIX`, `TERMODE_BIN`,
`TERMODE_WORKSPACES`, `TERMODE_TMPDIR`, `PATH`, `TMPDIR`, and `TERM`.

v0.44 adds a safe runtime package installer prototype:

```sh
runtime-pkg available
runtime-pkg install hello-bin
hello-bin
runtime-pkg verify hello-bin
runtime-pkg remove hello-bin
```

`hello-bin` is a tiny built-in script-tool stand-in for future binary/runtime
packages. It uses manifest validation, checksum verification, controlled
metadata, prefix/bin integration, and host interception. It is not real native
binary support yet.

See [docs/PREFIX_PATH_ENVIRONMENT.md](docs/PREFIX_PATH_ENVIRONMENT.md),
[docs/BINARY_PACKAGE_INSTALLER_PROTOTYPE.md](docs/BINARY_PACKAGE_INSTALLER_PROTOTYPE.md),
and [docs/RUNTIME_DECISION_FREEZE.md](docs/RUNTIME_DECISION_FREEZE.md).

## Screenshots

Screenshots are not checked into the repository yet. Add beta screenshots here
after the UI polish pass.

## Roadmap

- v0.42 Runtime Expansion Architecture
- v0.43 Prefix / PATH / Environment System
- v0.44 Binary Package Installer Prototype
- v0.45 Git Support Feasibility / Installer Path
- v0.46 Real Git Package Artifact / Execution Probe
- v0.47 Git Artifact Acquisition / Build Pipeline
- v0.48 Verified Git Artifact Bundle / Smoke Test (current)
- v0.49 Git Artifact Build / arm64-v8a Production
- v0.50+ Node.js / npm / Python / Dev Stack Presets
- v0.52 Full Terminal QA · v0.53 Complete Termode Beta
- CalypsoIDE integration later

Node/npm/Python/Git research stays deferred until after the standalone beta
stabilizes.

## Docs

- [Git Artifact Contract](docs/GIT_ARTIFACT_CONTRACT.md)
- [Git Artifact Acquisition](docs/GIT_ARTIFACT_ACQUISITION.md)
- [Git Build Pipeline](docs/GIT_BUILD_PIPELINE.md)
- [Git Bundle Smoke Test](docs/GIT_BUNDLE_SMOKE_TEST.md)
- [Git Support Strategy](docs/GIT_SUPPORT_STRATEGY.md)
- [Runtime Expansion Architecture](docs/RUNTIME_EXPANSION_ARCHITECTURE.md)
- [Binary Package Installer Prototype](docs/BINARY_PACKAGE_INSTALLER_PROTOTYPE.md)
- [Prefix / PATH / Environment](docs/PREFIX_PATH_ENVIRONMENT.md)
- [Release Notes v0.41](docs/RELEASE_NOTES_v0.41.md)
- [Release Notes v0.40](docs/RELEASE_NOTES_v0.40.md)
- [Beta Install](docs/BETA_INSTALL.md)
- [Beta Testing](docs/BETA_TESTING.md)
- [Getting Started](docs/GETTING_STARTED.md)
- [UI & Settings](docs/UI_SETTINGS.md)
- [Known Limitations](docs/KNOWN_LIMITATIONS.md)
- [Roadmap](docs/ROADMAP.md)
- [Command Guide](docs/COMMAND_GUIDE.md)
- [Beta Readiness](docs/BETA_READINESS.md)
- [Device QA Bug Bash](docs/DEVICE_QA_BUG_BASH.md)
