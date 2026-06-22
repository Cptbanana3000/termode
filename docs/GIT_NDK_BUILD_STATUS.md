# Git NDK Build Status (v0.51, extended to v0.56)

## Selected Path
Termode v0.56 selects **Path B: NDK environment partially available**.

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
- Perl is not available on the host `PATH` (required to generate header files during compilation)
- Git source tree has not been extracted/compiled (archives are staged)
- zlib dependency has not been extracted/compiled (archives are staged)
- no reviewed, checked-in cross-build recipe is enabled yet

Therefore no compile was attempted, no artifact or installable manifest was generated, and Git remains unavailable/not installed.

## Reproduce The Check
From the repository root:
```sh
dart tools/git-build/check_build_env.dart
```

This command reports `PARTIAL` because Perl is still missing.

## Runtime Result
- `git-build-status`: `PARTIAL`
- `git-artifact bundle-check`: `UNAVAILABLE` or `TEMPLATE_ONLY`
- `runtime-pkg install git`: refuses safely
- `git-version`: reports not installed; it never prints a fake version
- `git-smoke-test`: blocked until real Git is installed
- beta readiness: missing Git remains an accepted limitation

## Next Milestone
**v0.57 Git arm64 Build Attempt**

The next milestone will focus on attempting to run the arm64-v8a NDK cross-compilation once Perl and compiler checks pass.
