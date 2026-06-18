# Prefix / PATH / Environment System

Termode v0.43 turns the v0.42 runtime expansion plan into a safe, usable
environment layer. v0.44 builds on it with the `hello-bin` runtime package
prototype. Termode still does not install Git, Node.js, npm, Python, compilers,
or real native packages yet.

## Prefix

The Termode prefix is the app-private `files/usr` directory. This deliberately
matches the existing script-package prefix so installed `pkg` commands and
silent helper reload keep working.

Important paths:

- `TERMODE_HOME`: app-private home directory
- `TERMODE_PREFIX`: app-private `files/usr`
- `TERMODE_BIN`: app-private `files/usr/bin`
- `TERMODE_WORKSPACES`: app-private projects/workspaces directory
- `TERMODE_TMPDIR`: app-private prefix temp directory
- `TERMODE_CACHE`: app-private cache directory
- `TERMODE_CONFIG`: app-private config directory

Run:

```sh
prefix-info
prefix-status
prefix-init
prefix-doctor
```

`prefix-init` is idempotent and never deletes user files.

## PATH Overlay

The PATH strategy puts Termode-controlled commands first, then keeps Android
system paths available:

1. `TERMODE_BIN`
2. Termode helper scripts
3. Android/system shell paths

Run:

```sh
path-info
path-status
path-preview
path-doctor
```

Termode does not add external storage or path traversal entries to PATH.

## Environment

REAL PTY shell sessions receive:

- `TERMODE_HOME`
- `TERMODE_PREFIX`
- `TERMODE_BIN`
- `TERMODE_WORKSPACES`
- `TERMODE_TMPDIR`
- `TERMODE_CACHE`
- `TERMODE_CONFIG`
- `PATH`
- `HOME`
- `TMPDIR`
- `TERM`

Run:

```sh
env-info
env-status
env-preview
env-doctor
env-check
```

`env-check` prints shell `echo` commands for manual verification inside
`default-shell`.

## Env Script

`prefix-init` generates:

```sh
$TERMODE_PREFIX/etc/termode_env.sh
```

It contains quoted POSIX `export` lines for Termode's safe environment. Termode
does not source arbitrary user files.

Run:

```sh
env-script
```

## Bin Discovery

Termode can inspect its PATH without claiming future tools are installed:

```sh
bin-list
bin-which node
bin-which git
bin-doctor
```

If `node`, `git`, `npm`, or `python` are missing, that is expected. After
`runtime-pkg install hello-bin`, `bin-list` and `bin-which hello-bin` should see
the prototype command.

## Shims

Runtime shims live in `TERMODE_PREFIX/bin` and point only to controlled runtime
entrypoints. v0.44 can show `hello-bin` as a prototype shim after installation.
Future real runtime shims will use the same controlled location.

Run:

```sh
shim-info
shim-list
shim-doctor
```

## Ready Now

- Prefix directory creation and doctor checks
- PATH preview/status/doctor
- Environment preview/status/doctor
- REAL PTY environment injection
- Env script generation
- Bin discovery
- Runtime shim planning
- Runtime package prototype discovery with `hello-bin`

## Not Supported Yet

- Git install/support
- Node.js install/support
- npm install/support
- Python install/support
- Native binary package manager
- Full Linux distribution compatibility

Next milestone: v0.45 Git Support.
