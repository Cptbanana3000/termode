# Git NDK Build Status (v0.51, extended to v0.58)

## Selected Path
Termode v0.58 selects **Path B: Build attempt starts but fails**.

The checked Windows host has:
- Android SDK: `C:/Users/joell/AppData/Local/Android/Sdk`
- Android NDK: `28.2.13676358`
- target ABI: `arm64-v8a`
- NDK LLVM arm64 compiler: present
- NDK `make`: present
- SDK CMake `3.22.1`: present
- archive tool: present
- writable project output directory: yes
- Perl: present (v5.42.2)
- zlib: built successfully (output library at `tools/git-build/output/arm64-v8a/zlib/lib/libz.a`)

The Git build is blocked by:
- Windows shell/path build issues (Unix Makefile relies on shell features like `/bin/sh` which are unavailable under native Windows cmd/powershell)

Therefore, the build was attempted, zlib succeeded, but Git compilation failed as expected. Git remains unavailable/not installed.

## Reproduce The Check
From the repository root:
```sh
dart tools/git-build/check_build_env.dart
```

This command reports `READY`.

## Runtime Result
- `git-build-status`: `PARTIAL`
- `git-artifact bundle-check`: `UNAVAILABLE` or `TEMPLATE_ONLY`
- `runtime-pkg install git`: refuses safely
- `git-version`: reports not installed; it never prints a fake version
- `git-smoke-test`: blocked until real Git is installed
- beta readiness: missing Git remains an accepted limitation

## Next Milestone
**v0.59 Git Build Fixes**

The next milestone will focus on resolving the Unix build/Makefile shell compatibility issues on Windows hosts.
