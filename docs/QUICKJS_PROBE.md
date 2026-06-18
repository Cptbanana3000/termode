# Termode v0.33 QuickJS Probe

Termode v0.33 adds the `quickjs` command namespace and Android bridge surface
for a real embedded JavaScript engine probe. The actual QuickJS engine source is
not integrated in this build because no local vendored QuickJS snapshot exists
in the repository and this milestone must not add network-based build steps,
package-manager dependencies, or large unreviewed native code.

Source/version/origin:
- QuickJS source: not vendored
- Version: not integrated
- Origin: none in this repository

The probe therefore reports `LIMITED` or `UNAVAILABLE` cleanly rather than
pretending to run JavaScript.

## What QuickJS Is

QuickJS is a small embeddable JavaScript engine. It is a plausible future fit
for Termode because it can be compiled as native code and called through the
APK native-library/JNI path.

## What v0.33 Proves

v0.33 proves the command surface and bridge shape for a future engine:

```text
Dart command -> MethodChannel quickJs -> Android handler -> structured result
```

It also proves the user-facing safety behavior:
- code length is validated before evaluation
- file input is constrained to safe Termode workspace paths
- large output is truncated by the Dart service
- Node-style APIs are blocked before the bridge
- obvious infinite-loop patterns are blocked
- failures return clean messages

## What It Does Not Prove

v0.33 does not prove:
- real QuickJS evaluation
- Node.js compatibility
- npm compatibility
- package installation
- imports or `require`
- filesystem, network, process, or timer APIs
- Vite, Next.js, or dev-server behavior

## js-proof vs QuickJS vs Node.js

`js-proof` is the controlled built-in evaluator from v0.31. It supports only a
tiny expression subset and is safe as a routing proof.

`quickjs` is the future real-engine probe namespace. In this build it is
limited/unavailable because the engine source is not integrated.

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
- Loop guard: obvious `while(true)` and `for(;;)` patterns are blocked

Disabled APIs include `require`, `import`, `process`, `fs`, `http`, and `eval`.

## Commands

```sh
quickjs
quickjs help
quickjs info
quickjs eval "1 + 2"
quickjs file test.js
quickjs limits
quickjs doctor
quickjs plan
```

## Package Notes

Remote packages remain script-only. QuickJS is built into Termode as a probe
surface, not an installable package. QuickJS is not Node.js, and npm is not
available.

## v0.34 Update

v0.34 added the `duktape` fallback probe surface. Like `quickjs`, it is
limited/unavailable in this build because no local source snapshot is vendored.

## v0.35 Runtime Freeze

v0.35 freezes QuickJS as deferred. The `quickjs` command remains available as a
probe surface only; QuickJS source is not integrated and QuickJS is not a
package runtime.

The recommended next step is `v0.36 Product Stabilization / Beta Readiness
Pass`.

## Future Plan

1. QuickJS probe command/bridge surface
2. Duktape fallback probe command/bridge surface
3. Runtime decision freeze - complete; QuickJS deferred
4. Product stabilization
5. Revisit only after source policy, sandboxing, timeout/interruption, ABI/build, APK size, update/security, and device QA are solved
6. Node strategy much later
7. npm later
8. Vite later
