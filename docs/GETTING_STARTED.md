# Getting Started

Termode is a standalone Android terminal with REAL PTY shell sessions, script
packages, workspaces, and compact diagnostics.

## First Commands

Run these first:

```sh
welcome
commands
examples
glossary
doctor
qa-status
default-shell
pwd
pkg list
workspace
```

## Package Example

```sh
pkg list
pkg install hello
hello
pkg verify hello
pkg remove hello
pkg doctor
```

Packages are script packages. Native binary packages are not supported.

## Workspace Example

```sh
workspace-init demo
workspace-cd demo
pwd
host-write hello.txt "hello"
host-cat hello.txt
workspace-doctor
```

Workspaces live under Termode app storage.

## Doctor / QA Example

```sh
doctor
doctor --verbose
beta-status
beta-score
qa-status
onboarding-doctor
```

`READY WITH LIMITATIONS` can be acceptable when the limitations are documented,
such as frozen runtime work or unlinked Android storage.
