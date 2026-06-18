# Termode v0.35 Runtime Decision Freeze

Termode v0.35 freezes the runtime direction after the QuickJS and Duktape
probes. The goal is to stop runtime research drift and return focus to product
stability, terminal behavior, package polish, workspace polish, and device QA.

## Frozen Runtime Direction

The current supported runtime direction is:

- script packages through `/system/bin/sh`
- built-in native tools through JNI
- `js-proof` controlled evaluator
- localhost/preview workflow

This is the active path for Termode until a future milestone deliberately
reopens runtime work.

## Deferred

The following are explicitly deferred:

- QuickJS integration
- Duktape integration
- Node.js
- npm
- Python
- Git
- native package manager
- native binary package installs

Remote packages remain script-only. Native tools are built into Termode and are
not installable packages. `js-proof` is a built-in proof, not Node.js.

## Why QuickJS Is Deferred

QuickJS remains a useful candidate, but Termode does not yet have a clean
vendored source policy, engine sandbox policy, timeout/interruption strategy, or
device QA matrix for real embedded JavaScript engines. The `quickjs` command
surface remains available as a limited/unavailable probe surface only.

## Why Duktape Is Deferred

Duktape remains a simpler fallback candidate, but it has the same source,
sandboxing, timeout, ABI/build, APK size, update/security, and device QA
questions. The `duktape` command surface remains available as a
limited/unavailable probe surface only.

## Why js-proof Remains Active

`js-proof` is already small, controlled, and safe enough for the current runtime
proof. It proves bridge routing without exposing filesystem, network, process,
import, require, Node.js, or npm behavior. It is not a real JavaScript runtime.

## Why Node/npm Are Not Next

Node.js and npm are much larger than JS evaluation. They depend on native
runtime execution, ABI strategy, package layout, app storage behavior,
child_process decisions, file watching, npm scripts, update policy, and
security policy. Termode should not attempt them until the runtime strategy is
reopened with those constraints solved.

## Next Product Milestone

Recommended next milestone:

`v0.36 Product Stabilization / Beta Readiness Pass`

Focus:

- docs/help cleanup
- onboarding
- command discoverability
- device QA
- bug bash
- package polish
- workspace polish
- terminal UX polish

## Revisit Conditions

Real runtime work should only resume after these conditions are defined:

- clean vendored source policy
- sandbox/resource limits
- timeout/interruption strategy
- ABI/build strategy
- APK size decision
- update/security policy
- device QA
