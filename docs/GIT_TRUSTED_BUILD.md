# Git Trusted Build (v0.50, extended through v0.58)

This document defines the trusted production build requirements for a future Termode Git artifact.

## Goal
Produce a real Android `arm64-v8a` Git payload that Termode can validate, install into `TERMODE_PREFIX`, and execute with:
```sh
git --version
```

## Trust Requirements
The artifact source must be one of:
- `termode-built`: built by the Termode project from documented source
- `termode-vendored`: reviewed and vendored by the Termode project

Rejected sources:
- random internet binaries
- copied Termux binaries without provenance
- user-provided archives
- runtime downloads inside the Android app
- placeholder scripts that fake Git output

## Required Layout
```text
tools/runtime-artifacts/git/arm64-v8a/
  manifest.json
  files/
    bin/git
    lib/...       # only if required
    libexec/...   # only if required
    share/...     # only if required
  checksums/
    sha256.txt    # optional convenience copy
```

Do not include zero-byte placeholder payload files. Documentation files under `files/` are ignored by the manifest helper unless they live under allowed payload directories.

## Build Record
Before bundling, record:
- Git version
- source URL or source note
- source checksum
- dependency list and checksums
- Android NDK/toolchain version
- build command
- license review
- known runtime dependencies

## Manifest Generation
First run the host preflight environment checks:
```sh
dart tools/git-build/check_build_env.dart
dart tools/git-build/build_git_arm64.dart
```

Then create a real `build-inputs.json` (or a candidate `build-inputs.candidate.json`) and pass:
```sh
dart tools/git-build/check_build_inputs.dart
dart tools/git-build/verify_git_source.dart
dart tools/git-build/check_dependencies.dart
```

The example file is intentionally template-only and non-build-ready. A candidate manifest created via `create_build_inputs_candidate.dart` requires human review and promotion before the build pipeline is marked READY.

Use the host-side artifact helper only after real staged output exists:
```sh
dart tools/git-build/prepare_git_artifact.dart arm64-v8a tools/git-build/output/arm64-v8a/stage
```

The staging form writes a review-only candidate to:
```text
tools/runtime-artifacts/git/arm64-v8a/manifest.candidate.json
```

Review and promote it to `manifest.json` only after replacing incomplete metadata. Then validate:
```sh
dart tools/git-build/validate_git_artifact.dart arm64-v8a
```

## Runtime Verification
After bundling into a debug APK, install on Android and run:
```sh
git-artifact production-status
git-artifact bundle-check
runtime-pkg install git
git-version
git-exec-probe
git-smoke-test
git-doctor
```

Git support is not available until `git --version` succeeds on device.
