# Known Limitations

Termode is beta software. v0.45 proves the Git installer path on top of the
v0.44 runtime package installer prototype, but ships no Git artifact, so Git —
like Node/npm/Python — is still **planned, not installed**. Termode never fakes
Git; `git`, `git-version`, and `bin-which git` all report it as not installed.
See [Git Support Strategy](GIT_SUPPORT_STRATEGY.md).

Termode does not run Node.js, npm, Git, or Python yet. A `LIMITED` or
`PROTOTYPE READY`, `ARCHITECTURE PHASE`, or `LIMITED` status is often
intentional when it refers to frozen runtime work, unlinked Android storage,
planned toolchains, or a prefix that has not been initialized yet.

## Runtime Freeze

Runtime direction is frozen for the current beta foundation. Termode currently
supports:

- REAL PTY shell sessions
- script packages through `/system/bin/sh`
- built-in JNI native tools
- `js-proof` controlled evaluator
- localhost/preview diagnostics
- prefix/PATH/environment infrastructure for future tools
- runtime package installer prototype with `hello-bin`

## Not Included Yet

- Node.js/npm
- Python
- Git
- real native binary package installs
- native package manager
- full Linux distribution compatibility

QuickJS and Duktape remain probe surfaces only. They are not production
runtimes.

## Runtime Environment And Planned Toolchains

Git, Node.js, npm, Python, curl/wget, and editors are planned for future
milestones. v0.44 adds a safe prototype installer with `hello-bin`, but still
no real Git/Node/npm/Python installs, downloads, or native execution. Explore it
with:

```sh
prefix-status
path-status
env-status
bin-list
shim-info
toolchain-status
runtime-install status
runtime-pkg status
runtime-pkg available
runtime-abi
git-status
git-doctor
dev-doctor
```

See [Binary Package Installer Prototype](BINARY_PACKAGE_INSTALLER_PROTOTYPE.md),
[Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md), and
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
