# Git Trusted Build (v0.50)

This document defines the trusted production build requirements for a future
Termode Git artifact.

## Goal

Produce a real Android `arm64-v8a` Git payload that Termode can validate,
install into `TERMODE_PREFIX`, and execute with:

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

Do not include zero-byte placeholder payload files. Documentation files under
`files/` are ignored by the manifest helper unless they live under allowed
payload directories.

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

Use the host-side helper from the project root:

```sh
dart tools/git-build/prepare_git_artifact.dart arm64-v8a
```

Write the output to:

```text
tools/runtime-artifacts/git/arm64-v8a/manifest.json
```

Then validate:

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

