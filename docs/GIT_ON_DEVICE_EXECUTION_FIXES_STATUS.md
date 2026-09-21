# Git On-Device Execution Fixes Status - Termode v0.64

## Selected path

**Path A: real Git artifact executes successfully on Android.**

The v0.63 failure was not an invalid ELF or ABI mismatch. Android allowed the
exact bytes to run from an executable staging location but denied execution
after they were copied into Termode's writable app-private files directory.
v0.64 therefore stopped treating `chmod +x` as sufficient.

The APK now packages the Git 2.44.0 arm64-v8a ELF as
`lib/arm64-v8a/libtermode_git_exec.so` with legacy native-library extraction
enabled. Android extracts it beneath `applicationInfo.nativeLibraryDir`.
Termode validates that exact approved path, package name, ELF magic, ABI, byte
count, and SHA-256 before executing it through a constrained platform adapter.

The stable logical command remains `TERMODE_PREFIX/usr/bin/git`. It maps to
the immutable APK payload rather than copying the executable into writable
storage.

## Verified result

- Git: 2.44.0, minimal-local build
- ABI: arm64-v8a
- Bytes: 5,463,168
- SHA-256: `4a4883d3e0b18dc082ac99cdb3da5d80e2b988e2a801b418b0bebfe855a467e1`
- Android: 16 / API 36, arm64-v8a tablet
- extracted payload mode: executable by the Termode app UID
- `runtime-pkg install git`: PASS
- `runtime-pkg verify git`: PASS
- `bin-which git`: logical and backing mapping reported
- `git-version` and direct `git --version`: `git version 2.44.0`
- `git init` and `git status`: PASS in app-private workspace
- `git-smoke-test`: HEALTHY

Local Git support is enabled only for the verified initial commands. Remote Git
and advanced helpers remain deferred.
