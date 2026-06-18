# Bundled Runtime Proof (v0.28)

Termode v0.28 proves the safest future path for a real bundled runtime without
adding one. It ships a tiny native bridge proof inside the APK's native library
and exposes it through `bundled-runtime-*` commands.

**v0.28 does not include Node.js.** It also does not include npm, Python, Git,
native binary packages, downloaded executables, or any bundled runtime.

v0.30 adds native runtime candidate research. The recommended next proof is a
tiny embedded JS engine feasibility probe before Node.js.

## Current Android Execution Constraints

Android app-private storage commonly blocks direct execution of files placed in
paths such as `files/usr/bin`. A script can exist, be readable, and still fail
with `Permission denied` (exit code 126) when invoked directly. This is why
Termode runs script packages through `/system/bin/sh` rather than executing
app-written files directly, and why a future runtime cannot simply drop a
binary into app storage and run it.

## Why App-Writable `usr/bin` Execution Is Blocked/Limited

Modern Android mounts app-writable data directories in a way that prevents
executing files written there (W^X-style restrictions, `noexec`-like behavior
on app-private data on many devices/policies). The app can read and write those
files, but the OS refuses to exec them. Direct app-bin execution therefore
reports `blocked` in `runtime-doctor` and `runtime-exec-test`, and the bundled
proof reports `Bundled executable: blocked` on-device.

Native tools are built into Termode and exposed by the JNI bridge; they are not
installable packages. Remote packages remain script-only.

## Four Execution Mechanisms Compared

1. **Script packages through `/system/bin/sh`** — supported today. Termode
   writes a shell script under `usr/bin` and runs it as
   `/system/bin/sh "$TERMODE_BIN/<script>"`. The system shell is the executable;
   the script is just data, so the app-private exec restriction does not apply.

2. **Native bridge calls through JNI** — supported today, and the mechanism the
   v0.28 proof uses. Termode calls functions in its own bundled native library
   (`libtermode_pty.so`) loaded by the app. This already powers REAL PTY. It is
   the dependable, permission-clean way to run native code.

3. **APK-bundled native libraries** — `lib*.so` files packaged per-ABI inside
   the APK and loaded with `System.loadLibrary`. These are read-only and managed
   by Android. This is the realistic vehicle for shipping native runtime code.

4. **Standalone native executables** — a separate binary the app would try to
   exec. On app-private storage this is blocked/limited; doing it reliably tends
   to require extraction to an executable location, ABI matching, and careful
   process management, and it is fragile across devices. Not attempted in v0.28.

## What the v0.28 Proof Does

- `nativeProofToken()` returns the fixed string `termode-native-proof-ok`,
  proving Termode can call into its bundled native library and get a result.
- `nativeEchoProof("echo hello")` returns `hello` from native code, proving a
  tiny native-side command dispatcher works **without** launching a shell or any
  external process.
- The bridge also reports the device ABI, native pid, and native cwd.

Commands:

```sh
bundled-runtime-info     # ABI, native bridge, APK native layer, Node status, overall
bundled-runtime-test     # native bridge call, ABI, cwd, pid, echo proof, overall
bundled-runtime-doctor   # compact health (add --verbose for details)
bundled-runtime-paths    # native library, channel, cwd, and app HOME/USR/BIN
bundled-runtime-plan     # bundled runtime roadmap
```

## Future Possible Node Strategies

1. **Node as an APK-shipped native component** — package a Node native library
   per-ABI inside the APK and drive it through JNI. Most aligned with what
   v0.28 proves works.
2. **Node controlled through a native bridge** — keep process control on the
   native side reached through JNI, rather than direct app-private exec.
3. **Node executable strategy if Android allows** — only viable if a future
   Android target reliably allows executing an extracted binary; today this is
   blocked/limited on app-private storage.
4. **Fallback: no Node until a safe strategy is proven** — Termode stays
   runtime-free rather than shipping a fragile or unsafe execution path.

## Recommended Next Step

Use runtime candidate research to choose the safest next proof. The current
recommendation is a tiny embedded JS engine feasibility probe before attempting
Node.js.
