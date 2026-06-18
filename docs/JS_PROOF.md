# Tiny JS Proof (v0.31)

Termode v0.31 adds `js-proof`, a tiny JavaScript-like feasibility probe. It is
not Node.js, not npm, and not a real package ecosystem.

## What It Proves

`js-proof` proves that Termode can route code through:

```text
Dart -> Kotlin MethodChannel -> JNI/native library -> structured result
```

The native side evaluates a very small controlled syntax subset and returns
either a result or a clean error. It does not spawn a shell, launch an external
process, write files, access the network, or execute app-writable binaries.

## What It Does Not Prove

- Node.js compatibility
- npm compatibility
- Vite or Next.js support
- imports or `require`
- filesystem APIs
- network APIs
- timers
- package installation
- real JavaScript engine embedding

## Tiny Proof vs Embedded JS Engine vs Node

Tiny JS proof:
- Built into Termode.
- Uses a controlled evaluator in the existing native library.
- Supports only small expressions.

Embedded JS engine:
- A future possibility such as QuickJS, Duktape, JavaScriptCore, or V8.
- Would need a new size, ABI, API, safety, and lifecycle review.

Node.js:
- A later goal with much higher risk.
- Brings npm, child processes, native modules, file watching, and large binary
  size concerns.

## Supported Subset

- numbers
- arithmetic: `+`, `-`, `*`, `/`
- parentheses
- string literals such as `'hello'` or `"hello"`
- booleans: `true`, `false`

Unsupported syntax returns:

```text
Error: Unsupported JS proof syntax.
This is not Node.js.
```

## Safety Limits

- Max inline code length: 4096 characters
- Max file size: 32768 bytes
- File input must resolve inside safe Termode home/workspace roots
- No imports
- No `require`
- No filesystem API
- No network API
- No timers
- No shell commands
- No app-writable binary execution

## Commands

```sh
js-proof
js-proof info
js-proof eval "1 + 2"
js-proof eval "1 + 2 * 3"
js-proof eval "'hello'"
js-proof file test.js
js-proof limits
js-proof doctor
js-proof plan
```

## Future Path

1. Tiny JS proof
2. Real embedded JS engine research
3. Node runtime strategy
4. npm strategy
5. dev server workflow

Remote packages remain script-only. `js-proof` is built in, not an installable
package. Node.js and npm are not available yet.
