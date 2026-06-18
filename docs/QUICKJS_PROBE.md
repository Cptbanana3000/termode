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

## Future Plan

1. QuickJS probe command/bridge surface
2. QuickJS safety hardening if a source snapshot is integrated later
3. Duktape or smaller embedded-engine fallback if QuickJS remains too large
4. Optional JS script package bridge much later
5. Node strategy much later
6. npm later
7. Vite later
