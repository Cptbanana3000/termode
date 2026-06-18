# Termode JS Engine Decision

Termode v0.32 introduced the JS engine decision layer. v0.33 adds the
`quickjs` command and Android bridge surface, but does not integrate QuickJS
source because no local vendored snapshot exists in the repository.

This work does not add Node.js, npm, Python, Git, native package downloads, a
JS package manager, or app-writable binary execution.

## Current Status

`js-proof` remains the safe current working evaluator. It routes code through:

```text
Dart command -> Kotlin MethodChannel -> JNI/native C++ -> result
```

The proof supports a tiny controlled JavaScript-like subset: numbers,
arithmetic, parentheses, strings, and booleans. It blocks Node-like features
such as `require`, `import`, `process`, `fs`, `http`, and `eval`.

`js-proof` is not Node.js and is not a real JavaScript engine. It proves the
route and safety model, not compatibility with browser JavaScript, Node, npm,
or packages.

`quickjs` is now available as a limited/unavailable probe surface. It reports
cleanly that the engine source is not integrated in this build. See
[QUICKJS_PROBE.md](QUICKJS_PROBE.md).

## Candidate Summary

```text
current-proof     current   safest
quickjs           possible  promising
duktape           possible  simple
javascriptcore    risky     platform-dependent
v8                risky     large
node              future    not yet
no-engine-yet     fallback  safest
```

## QuickJS

QuickJS is the strongest next candidate for a small real JavaScript engine
probe. It is compact, embeddable as C, and modern enough for a meaningful
JavaScript proof.

Pros:
- Small real JavaScript engine.
- Plausible fit for the existing JNI/native bridge.
- Better compatibility signal than the custom `js-proof` evaluator.

Cons:
- Requires source vendoring and CMake/JNI integration.
- Needs output, memory, and runaway-script controls.
- Native crashes can affect the app process.

v0.33 result: the command/bridge surface was added, but engine integration was
deferred because no source snapshot was available locally.

Recommendation: do not expose QuickJS evaluation until source vendoring,
timeout/interruption, memory/output limits, and crash behavior are solved.

## Duktape

Duktape is a simpler mature embeddable JavaScript engine. It is less modern
than QuickJS, but may be easier to integrate as a first real-engine fallback.

Recommendation: use Duktape as the v0.34 fallback if QuickJS remains too large,
unavailable, or hard to interrupt safely.

## JavaScriptCore, V8, And Node

JavaScriptCore is platform-dependent for this use case and not ideal for early
Android runtime work.

V8 is powerful but large and complex. It is not suitable for the next Termode
milestone.

Node is not just a JavaScript engine. It brings libuv, process behavior,
filesystem APIs, module loading, npm expectations, native modules, script
hooks, and dev-server behavior. Node remains a future goal after smaller
runtime proofs succeed.

## Security Concerns

Any real embedded engine must handle:

- infinite loops and timeout/interrupt behavior
- memory growth inside the app process
- native crashes
- filesystem, network, process, `require`, and `import` exposure
- output size limits
- APK size across ABIs
- build and supply-chain maintenance

If infinite loop protection cannot be implemented, loops should be blocked or
the real engine should stay behind a research-only proof.

## Current Decision

Real engine integration is still deferred. The current working proof remains
`js-proof`, while `quickjs` is a limited bridge/command probe.

Recommended next step: `v0.34 Duktape Probe / Engine fallback`.

Fallback: keep the current proof longer if no engine can be added safely.
