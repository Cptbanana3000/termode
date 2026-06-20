# Git Android NDK Source Build (extended in v0.52)

This is the reviewed plan for producing Termode's first real Git artifact. It
is a host-side process and never runs inside the Android app.

## Target

- ABI: `arm64-v8a`
- minimum initial Android API assumption: API 21 or newer
- first proof: real `git --version`
- second proof: local `git init` and `git status`
- HTTPS clone/pull: later, after its dependency and TLS strategy are reviewed

## Source And License Gate

Git and every dependency must have a recorded version, upstream URL, license,
archive/tree SHA-256, and review note. Allowed artifact trust labels remain
`termode-built` and `termode-vendored`. Random binaries, copied Termux payloads,
runtime downloads, and user archives are rejected.

Git is GPL-2.0-only. Dependency licenses and notices must be reviewed before a
payload is bundled.

## Dependencies

- zlib: expected for the minimal useful build
- libcurl: required when HTTPS remotes are enabled
- TLS: reviewed OpenSSL build or another explicit Android-compatible strategy
- expat and PCRE2: include only if selected features require them

The minimal `git --version`/local-repository proof may deliberately disable
optional remote and localization features. That is not equivalent to complete
Git remote support.

## Build Stages

1. Acquire trusted Git source.
2. Acquire and verify dependency sources.
3. Configure the NDK arm64 cross compiler and sysroot.
4. Build dependencies, then Git.
5. Stage runtime files under `tools/git-build/output/arm64-v8a/stage/`.
6. Prepare a candidate manifest and per-file SHA-256 values.
7. Review metadata, then validate manifest, ABI, paths, bytes, and hashes.
8. Bundle through the trusted registry and install through `runtime-pkg`.
9. Run real `git --version` and the Android smoke checklist.

## Host Commands

```sh
dart tools/git-build/check_build_env.dart
dart tools/git-build/check_build_inputs.dart
dart tools/git-build/verify_git_source.dart
dart tools/git-build/check_dependencies.dart
dart tools/git-build/build_git_arm64.dart
dart tools/git-build/prepare_git_artifact.dart arm64-v8a tools/git-build/output/arm64-v8a/stage
dart tools/git-build/validate_git_artifact.dart arm64-v8a
```

`prepare_git_artifact.dart` writes `manifest.candidate.json`, not an installable
`manifest.json`, when staging input is supplied. Promotion requires human
review and successful validation. It rejects missing output, unsupported or
unsafe paths, zero-byte files, and conflicting destination payloads.

v0.52 requires the acquisition checks to pass before the build preflight may
consume source inputs. The checked-in example is template-only and cannot make
the build ready.

## Android Acceptance

An artifact is not Git support until all of these succeed on Android:

```sh
git-artifact bundle-check
runtime-pkg install git
git-version
git-exec-probe
git-smoke-test
git-doctor
bin-which git
shim-list
runtime-pkg verify git
```
