# Git NDK Build Status (v0.51, extended in v0.52)

## Selected Path

Termode v0.51 selects **Path B: NDK environment partially available**.

The checked Windows host has:

- Android SDK: `C:/Users/joell/AppData/Local/Android/Sdk`
- Android NDK: `28.2.13676358`
- target ABI: `arm64-v8a`
- NDK LLVM arm64 compiler: present
- NDK `make`: present
- SDK CMake `3.22.1`: present
- archive tool: present
- writable project output directory: yes

The build is blocked by:

- no reviewed Git source tree under `tools/git-build/sources/git/`
- no reviewed dependency sources under `tools/git-build/deps/`
- Perl is not available on the host `PATH`
- no reviewed, checked-in cross-build recipe is enabled yet

Therefore no compile was attempted, no artifact or installable manifest was
generated, and Git remains unavailable/not installed.

## Reproduce The Check

From the repository root:

```sh
dart tools/git-build/check_build_env.dart
dart tools/git-build/build_git_arm64.dart
```

The first command reports `PARTIAL`. The second is a safe preflight: it exits
without compiling or creating an artifact while required inputs are missing.

## Runtime Result

- `git-build-status`: `PARTIAL`
- `git-artifact bundle-check`: `UNAVAILABLE` or `TEMPLATE_ONLY`
- `runtime-pkg install git`: refuses safely
- `git-version`: reports not installed; it never prints a fake version
- `git-smoke-test`: blocked until real Git is installed
- beta readiness: missing Git remains an accepted limitation

## Next Milestone

v0.52 completes that acquisition plan and adds non-downloading host checkers,
but real inputs remain missing. See
[Git Source Acquisition Status](GIT_SOURCE_ACQUISITION_STATUS.md).

**v0.53 Git Source + Dependency Preparation**

The next safe input is a trusted Git source archive/tree with its version,
license, upstream provenance, and SHA-256 checksum, followed by reviewed
dependency sources.
