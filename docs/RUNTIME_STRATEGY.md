# Termode Runtime Strategy

Termode treats runtime work as a measured proof sequence. The current
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
- Native tools are built into Termode and exposed through JNI; they are not
  installable packages.
- `js-proof` is the current safe JavaScript-like proof.
- JS engine decision commands compare QuickJS, Duktape, JavaScriptCore, V8,
  Node, and no-engine-yet before any real engine is added.
- `quickjs` is a v0.33 limited/unavailable probe surface. QuickJS source is
  not integrated in this build.

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
2. Keep runtime diagnostics visible for shell, Toybox, and script probes.
3. Prove localhost and port diagnostics before adding any dev server runtime.
4. Add one bundled native runtime proof binary to validate ABI and execution.
5. Keep tiny native tools as built-in audited capabilities, not packages.
6. Research native runtime candidates.
7. Prove a tiny JS/runtime path before Node with `js-proof`.
8. Decide whether to ship a real embedded JS engine with `js-engine-*`.
9. Add the QuickJS probe command/bridge surface.
10. Harden embedded-engine safety before broad script execution.
11. Add a Node runtime proof after native execution behavior is understood.
12. Prove npm install/cache behavior inside app storage.
13. Prove a minimal Vite dev server.
14. Integrate CalypsoIDE workflows after runtime support is proven.

## Risks

- Direct app-private execution may be blocked on many devices.
- ABI mismatch can break bundled binaries.
- Extracted runtimes can be large and slow to initialize.
- npm-style dependency trees can stress storage and update flows.
- Long-running dev servers need careful PTY/session lifecycle handling.
- Remote binaries require a much stricter trust model than remote scripts.

## Recommended Next Proof

The current runtime target is still the tiny `js-proof` evaluator, not Node.
v0.33 adds the QuickJS command/bridge probe, but QuickJS source is not
integrated. The recommended next proof is a Duktape or smaller engine-source
fallback, unless QuickJS can be safely vendored with timeout/resource limits.

## Bundled Runtime Proof Findings (v0.28)

v0.28 adds a Bundled Runtime Proof Strategy. See
[BUNDLED_RUNTIME_PROOF.md](BUNDLED_RUNTIME_PROOF.md) for the full breakdown.

What v0.28 proves:

- Termode can call into its own bundled native library (`libtermode_pty.so`)
  through JNI and receive a result. The proof returns a fixed token
  (`termode-native-proof-ok`), the device ABI, the native pid, and the native
  cwd, exposed via `bundled-runtime-info`, `bundled-runtime-test`, and
  `bundled-runtime-doctor`.
- A tiny native-side command dispatcher proof handles a literal `echo hello`
  inside native code and returns `hello`. It runs no shell and no external
  process. This proves native bridge command handling without executing
  external code.

Native bridge calls: working. The proof is delivered entirely through the
existing NDK/JNI layer that already powers REAL PTY, so it adds no new runtime
and no new permissions.

Direct bundled executable invocation: not attempted in v0.28. Termode does not
ship a standalone native executable. Android blocks execution from
app-writable paths, so `bundled-runtime-doctor` reports
`Bundled executable: blocked` on-device (and `unknown` off-device). The safe,
proven path is JNI/native-library calls, not app-private executable launches.

Why this matters for future Node.js: it shows the dependable mechanism for any
future bundled runtime is the APK native layer reached through JNI, rather than
trying to drop and execute a binary in app storage. A future Node strategy
should be evaluated as an APK-shipped native component driven through a native
bridge.

Recommended next step: v0.34 Duktape Probe / Engine fallback (still no
Node/npm), using the criteria in [JS_ENGINE_DECISION.md](JS_ENGINE_DECISION.md)
and [QUICKJS_PROBE.md](QUICKJS_PROBE.md).
