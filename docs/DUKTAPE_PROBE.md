# Termode v0.34 Duktape Probe

Termode v0.34 adds the `duktape` command namespace and Android bridge surface
for a Duktape embedded JavaScript engine fallback probe. The actual Duktape
engine source is not integrated in this build because no local vendored Duktape
snapshot exists in the repository and this milestone must not add network-based
build steps, package-manager dependencies, or unreviewed native code.

Source/version/origin:
- Duktape source: not vendored
- Version: not integrated
- Origin: none in this repository

The probe reports `LIMITED` or `UNAVAILABLE` cleanly rather than pretending to
run JavaScript.

## What Duktape Is

Duktape is a small, mature embeddable JavaScript engine. It is generally simpler
than larger engines and can be attractive for constrained native integrations,
though its JavaScript support is less modern than QuickJS.

## Why Probe Duktape After QuickJS

v0.33 added the QuickJS command/bridge probe, but QuickJS source was not
integrated because no clean local vendored snapshot existed. Duktape is the
fallback candidate because it may be smaller and simpler to audit if a source
snapshot is added later.

## What v0.34 Proves

v0.34 proves the command surface and bridge shape for the fallback engine:

```text
Dart command -> MethodChannel duktape -> Android handler -> structured result
```

It also proves the user-facing safety behavior:
- code length is validated before evaluation
- file input is constrained to safe Termode workspace paths
- large output is truncated by the Dart service
- Node-style APIs are blocked before the bridge
- obvious infinite-loop patterns are blocked
- failures return clean messages

## What It Does Not Prove

v0.34 does not prove:
- real Duktape evaluation
- Node.js compatibility
- npm compatibility
- package installation
- imports or `require`
- filesystem, network, process, or timer APIs
- Vite, Next.js, or dev-server behavior

## js-proof vs QuickJS vs Duktape vs Node.js

`js-proof` is the controlled built-in evaluator from v0.31. It supports only a
tiny expression subset and is safe as the current working proof.

`quickjs` is the v0.33 real-engine probe namespace. In this build it is
limited/unavailable because QuickJS source is not integrated.

`duktape` is the v0.34 fallback-engine probe namespace. In this build it is
limited/unavailable because Duktape source is not integrated.

Node.js is a full runtime with libuv, process behavior, filesystem APIs, module
loading, npm expectations, and dev-server complexity. Node.js is not included.

npm is not available.

Vite/Next.js are later goals after a runtime strategy is proven.

## Safety Limits

- Max inline code length: 4096 chars
- Max file size: 32768 bytes
- Max output length: 8192 chars
- Filesystem: disabled
- Network: disabled
- Node APIs: disabled
- npm: unavailable
- Timeout: not supported yet
- Loop guard: limited; obvious `while(true)` and `for(;;)` patterns are blocked

Disabled APIs include `require`, `import`, `process`, `fs`, `http`, and `eval`.

## Commands

```sh
duktape
duktape help
duktape info
duktape eval "1 + 2"
duktape file test.js
duktape limits
duktape doctor
duktape plan
```

## Package Notes

Remote packages remain script-only. Duktape is built into Termode as a probe
surface, not an installable package. Duktape is not Node.js, and npm is not
available.

## Future Plan

1. Duktape probe command/bridge surface
2. Runtime decision freeze - complete; Duktape deferred
3. Product stabilization
4. Revisit only after source policy, sandboxing, timeout/interruption, ABI/build, APK size, update/security, and device QA are solved
5. Node strategy much later
6. npm later
7. Vite later

## v0.35 Runtime Freeze

v0.35 freezes Duktape as deferred. The `duktape` command remains available as a
probe surface only; Duktape source is not integrated and Duktape is not a
package runtime.

The recommended next step is `v0.36 Product Stabilization / Beta Readiness
Pass`.
