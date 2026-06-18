# Native Runtime Candidates

Termode v0.30 is a research milestone. It compares possible runtime strategies
before attempting Node.js, npm, Python, Git, native package downloads, or any
real runtime installation.

## 1. Script Packages Through /system/bin/sh

This is the current working package system. Packages install scripts into
`files/usr/bin`, and shell helpers invoke them through `/system/bin/sh`.

Strengths:
- Best for lightweight tools.
- Works today in NORMAL mode and REAL PTY mode.
- Avoids Android app-writable executable restrictions.
- Fits the current remote trust/source-lock model.

Limits:
- Not enough for Node/npm.
- Limited by Android shell and Toybox availability.
- Not a native runtime strategy.

## 2. JNI / Native Bridge Tools

The v0.29 `native-tool` proof exposes a fixed set of tiny audited native
capabilities through the JNI/native bridge.

Strengths:
- Safe for small built-in native capabilities.
- No shell, no external process, no writable binary execution.
- Good for primitives such as hashing, ABI checks, pid, cwd, and diagnostics.

Limits:
- Not a general runtime package system.
- Not installable through `pkg`.
- Every capability must be audited and shipped with the app.

## 3. APK Native Libraries

APK native libraries are the Android-supported path for bundled native code.
They are promising for embedded runtimes that can be called as libraries.

Strengths:
- Android-supported native distribution model.
- ABI-specific and app-shipped.
- Avoids direct execution from app-writable locations.

Limits:
- Harder if a runtime expects to be a standalone process.
- Native crashes can still terminate the app process.
- APK size grows with every ABI and runtime component.

## 4. Bundled Executable

A standalone bundled executable could be useful if it lives in an Android-
supported executable location, but it is risky.

Risks:
- App-writable `files/usr/bin` execution is commonly blocked.
- Process lifecycle, permissions, and updates need separate proof.
- Downloaded native executables are not acceptable yet.

This path needs a tiny proof before it can be trusted.

## 5. Embedded JS Engine

An embedded JavaScript engine is the recommended next feasibility step before
Node. Candidate engines to research later include QuickJS, Duktape,
JavaScriptCore, and V8.

Strengths:
- Proves JavaScript evaluation without npm.
- Smaller and more controllable than Node.
- Fits the APK-native-library/JNI research path.

Limits:
- Not Node-compatible by itself.
- No npm, dev server, file watching, or child-process support yet.
- Requires sandboxing and careful API exposure.

## 6. Node Binary

Node is a future goal, not the next experiment.

Risks:
- Large APK or runtime payload.
- ABI-specific builds.
- Execution model uncertainty.
- npm scripts, symlinks, native modules, child processes, file watching, and
  package trust.

Node should wait until Termode proves a safe runtime strategy.

## 7. Termux-Style Prefix

A Termux-style prefix is powerful but far too complex for the current stage.
It implies package patches, mirrors, ABI management, updates, security review,
and a large ecosystem maintenance burden.

This is not suitable yet.

## 8. Remote-Only / Cloud Execution

Remote execution is a fallback idea. It is technically easier in some ways but
works against the offline/local IDE dream.

It also introduces accounts, network dependency, workspace sync, transport
security, and trust concerns.

## Recommendation

Short term:
- Keep script packages as the stable package system.
- Keep JNI native tools for audited built-in capabilities.

Next proof:
- `v0.31 Tiny Embedded JS Engine Feasibility Probe`

Fallback proof if embedded JS blocks:
- `v0.31 Tiny APK Native Executable Probe`

Later:
- Attempt Node only after the runtime strategy is proven.
