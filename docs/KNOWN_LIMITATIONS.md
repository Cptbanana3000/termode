# Known Limitations

Termode is beta software. The current goal is to stabilize the standalone
terminal experience before expanding runtimes.

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

## Android / Storage Limits

- Storage features need the user to link an Android folder.
- Direct app-bin execution may be blocked by Android on some devices.
- Some terminal behavior may differ from desktop Linux.
- Preview commands need an external browser for `preview-open`.

## What To Run

```sh
beta-known-limits
runtime-freeze status
runtime-freeze deferred
runtime-freeze why
doctor
qa-status
```
