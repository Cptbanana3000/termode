# Known Limitations

Termode is beta software. v0.43 provides the prefix/PATH/environment layer for
future toolchains, but those toolchains are **planned, not installed**.

Termode does not run Node.js, npm, Git, or Python yet. A `LIMITED` or
`ARCHITECTURE PHASE` status is often intentional when it refers to frozen
runtime work, unlinked Android storage, planned toolchains, or a prefix that has
not been initialized yet.

## Runtime Freeze

Runtime direction is frozen for the current beta foundation. Termode currently
supports:

- REAL PTY shell sessions
- script packages through `/system/bin/sh`
- built-in JNI native tools
- `js-proof` controlled evaluator
- localhost/preview diagnostics
- prefix/PATH/environment infrastructure for future tools

## Not Included Yet

- Node.js/npm
- Python
- Git
- native binary package installs
- native package manager
- full Linux distribution compatibility

QuickJS and Duktape remain probe surfaces only. They are not production
runtimes.

## Runtime Environment And Planned Toolchains

Git, Node.js, npm, Python, curl/wget, and editors are planned for future
milestones. v0.43 adds safe prefix/PATH/env infrastructure but still no real
installs, downloads, or native execution. Explore it with:

```sh
prefix-status
path-status
env-status
bin-list
shim-info
toolchain-status
runtime-install status
dev-doctor
```

See [Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md) and
[Runtime Expansion Architecture](RUNTIME_EXPANSION_ARCHITECTURE.md).

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
prefix-status
path-status
env-status
toolchain-status
runtime-install status
doctor
qa-status
```
