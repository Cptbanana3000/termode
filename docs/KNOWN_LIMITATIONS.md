# Known Limitations

Termode is beta software. v0.42 builds the runtime expansion architecture: the
foundation for future toolchains (Git, Node.js, npm, Python, editors). Those
toolchains are **planned, not installed** — Termode does not run Node/npm/Git/
Python yet. A `LIMITED` / `ARCHITECTURE PHASE` status is an intentional state
(frozen runtime foundation, unlinked storage, planned toolchains) and does not
mean Termode is broken.

## Runtime Freeze

Runtime direction is frozen. Termode currently supports:

- REAL PTY shell sessions
- script packages through `/system/bin/sh`
- built-in JNI native tools
- `js-proof` controlled evaluator
- localhost/preview diagnostics

## Not Included Yet

- Node.js/npm
- Python
- Git
- native binary package installs
- native package manager
- full Linux distribution compatibility

QuickJS and Duktape are probe surfaces only. They are not production runtimes.

## Runtime Expansion (Planned, Not Installed)

Git, Node.js, npm, Python, curl/wget, and editors (nano/micro) are planned for
future milestones. v0.42 adds only the planning/architecture surface — no real
installs, downloads, or native execution. Explore it with:

```sh
toolchain-status
toolchain-list
runtime-install list
dev-doctor
prefix-info
```

See [Runtime Expansion Architecture](RUNTIME_EXPANSION_ARCHITECTURE.md).

## Android / Storage Limits

- Storage features need the user to link an Android folder.
- Direct app-bin execution may be blocked by Android on some devices.
- Some terminal behavior may differ from desktop Linux.
- Preview commands need an external browser for `preview-open`.

## What To Run

```sh
beta-known-limits
runtime-freeze status
runtime-freeze why
toolchain-status
runtime-install status
doctor
qa-status
```
