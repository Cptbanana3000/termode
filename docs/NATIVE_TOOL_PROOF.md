# Tiny Native Tool Proof (v0.29)

Termode v0.29 proves that small, audited utilities can be exposed safely through
the existing JNI/native bridge — without executing app-writable binaries and
without adding a real runtime such as Node.js.

**v0.29 does not include Node.js, npm, Python, Git, or a native package
manager.**

v0.30 runtime candidate research keeps native tools as built-in capabilities,
not packages, and recommends a tiny embedded JS engine feasibility probe before
attempting Node.js.

## What `native-tool` Proves

The `native-tool` command exposes a fixed, audited set of utilities implemented
inside the bundled native library (`libtermode_pty.so`) and reached through the
`nativeTool` method channel:

```sh
native-tool              # help and available subcommands
native-tool info         # native bridge, ABI, PID, CWD, tool list
native-tool echo <text>  # echo text from native code
native-tool cwd          # native current working directory
native-tool pid          # native process id
native-tool abi          # ABI the native library was compiled for
native-tool hash <text>  # SHA-256 of text, computed in native C++
native-tool time         # native timestamp (epoch ms)
native-tool env          # safe, limited environment summary
native-tool doctor       # bridge/echo/cwd/abi/hash health
```

The hash is a real SHA-256 implemented in the native library and labelled
`Hash type: SHA-256`. The env summary only ever exposes a fixed whitelist
(`HOME`, `TMPDIR`, `TERMODE_HOME`, `TERMODE_USR`, `TERMODE_BIN`); no other
environment variables are returned, and anything outside the whitelist is
dropped on the Dart side as defense in depth.

## Why It Avoids App-Writable Binary Execution

Android commonly blocks executing files written into app-private storage (such
as `files/usr/bin`). Instead of dropping and running a binary, `native-tool`
calls functions that are already compiled into the APK's native library and
loaded with `System.loadLibrary`. Nothing is written to disk to be executed,
nothing is downloaded, no shell is spawned, and no external process is started.

## Why JNI/Native Bridge Is Safer for Audited Tools

- The code is compiled into the APK and signed with it — it cannot be swapped
  at runtime.
- It runs in-process via JNI, so there is no `exec` of app-writable files and no
  child-process management.
- It requires no extra permissions and no root.
- Failures are caught and reported as `Native tool bridge unavailable. Runtime
  remains limited.` rather than crashing the app.

## Four Mechanisms Compared

1. **Script package** — a shell script under `usr/bin` run as
   `/system/bin/sh "$TERMODE_BIN/<script>"`. The system shell is the executable;
   the script is data. Installable via `pkg`, script-only.
2. **Native bridge tool** — what v0.29 adds. A function compiled into the APK's
   native library, called through JNI. Built into Termode, not installable.
3. **Native executable** — a standalone binary the app would try to `exec` from
   storage. Blocked/limited on app-private storage; not used.
4. **Future runtime** — a large runtime such as Node.js. Not included; would
   need to ship as an APK native component reached through a bridge, proven
   first.

## What v0.29 Does Not Include

- Node.js
- npm
- Python
- Git
- a native package manager (packages remain script-only)

## Future Next Step

Tiny embedded JS engine feasibility probe: prove runtime-style JavaScript
evaluation through the APK native-library/JNI path before attempting Node.js.
