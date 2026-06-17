# Termode Runtime Strategy

Termode v0.25 treats runtime work as a measured proof sequence. The current
runtime is shell-first: REAL PTY sessions run Android `/system/bin/sh`, Termode
host-intercepts management commands such as `pkg`, and installed packages are
script packages executed through shell helper functions.

## Current Runtime Shape

- REAL PTY shell sessions are the primary UX.
- Script packages install into `files/usr/bin`.
- Package commands run through helper functions that call `/system/bin/sh`.
- Remote packages are supported only for script packages and only after repo
  trust/source checks.
- Workspace files live under `files/home/projects`.

## Android Execution Restrictions

Android app-private storage commonly blocks direct execution from paths such as
`files/usr/bin`. A script can exist, be readable, and still fail with
`Permission denied` when called directly. Termode works around this by invoking
scripts with:

```sh
/system/bin/sh "$TERMODE_BIN/<script>"
```

This is why script packages work today while native binary packages are not
declared supported.

## Not Supported Yet

- Native binary packages
- Node.js
- npm
- Python
- Git

These runtimes need explicit ABI, extraction, permission, storage, and process
management proofs before they become package types.

## Future Strategies

1. Keep script packages stable and source-locked.
2. Add one bundled native runtime proof binary to validate ABI and execution.
3. Add a Node runtime proof after native execution behavior is understood.
4. Prove npm install/cache behavior inside app storage.
5. Prove a minimal Vite dev server.
6. Connect localhost preview once server lifecycle is reliable.
7. Integrate CalypsoIDE workflows after runtime support is proven.

## Risks

- Direct app-private execution may be blocked on many devices.
- ABI mismatch can break bundled binaries.
- Extracted runtimes can be large and slow to initialize.
- npm-style dependency trees can stress storage and update flows.
- Long-running dev servers need careful PTY/session lifecycle handling.
- Remote binaries require a much stricter trust model than remote scripts.

## Recommended Next Proof

The next runtime target should be a tiny bundled native binary proof, not Node.
It should report `native-ok`, ABI, pid, and cwd, and it should be tested across
devices before any large runtime is added.
