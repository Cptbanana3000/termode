# Git Artifact Production Status (v0.50, extended through v0.56)

## Selected Path
Termode v0.56 selects **Path B: reproducible build pipeline completed, no artifact yet**.

No real trusted Git artifact is present in this repository or bundled APK. Git therefore remains unavailable, `runtime-pkg install git` refuses safely, and no Termode command fakes `git --version`.

## Current State
- target tool: Git
- target ABI: `arm64-v8a`
- real Git artifact: no
- installable manifest: no
- Git installed: no
- Git executable: no
- production pipeline: ready
- `git-artifact production-status`: reports Path B
- beta readiness: unaffected by missing Git

## Why No Artifact Ships Yet
This checkout does not contain:
- a reproducible Android Git build output
- a reviewed `arm64-v8a` payload under `tools/runtime-artifacts/git/arm64-v8a/files/`
- a real installable `manifest.json`
- a successful Android `git --version` proof

(Note: Git 2.44.0 and zlib 1.3.1 source archives have been staged in v0.55 and Perl resolution/readiness is verified in v0.56, but compiled binaries are not produced yet.)

## Production Gate
Git can be marked available only after all of these pass:
1. real trusted payload staged under `tools/runtime-artifacts/git/arm64-v8a/files/`
2. manifest generated with safe relative paths, SHA-256 hashes, and byte counts
3. `git-artifact bundle-check` reports `AVAILABLE`
4. `runtime-pkg install git` succeeds
5. `git-version` prints a real Git version
6. `git-smoke-test` reports `HEALTHY`
7. workspace smoke commands are manually run on Android

## Milestone History
v0.51 adds the NDK/source-build environment detector and preflight. The local NDK is present, but source/dependency inputs are missing, so the production artifact remains unavailable. See [Git NDK Build Status](GIT_NDK_BUILD_STATUS.md).

v0.52 adds source/dependency input manifests and host verification. Real inputs remain missing, so the artifact remains unavailable.

v0.53 selects the Git version (2.44.0), documents the Perl build blocker, defines the minimal zlib dependency strategy, and prepares manifest templates.

v0.54 resolves host build prerequisites, provides Perl checks, specifies GPL-2.0-only / zlib staging rules, and creates a candidate build manifest template.

v0.55 stages the Git and zlib source archives on the host and promotes the build-inputs.json manifest, validating their SHA-256 checksums.

v0.56 hardens Perl detection on the host, documents manual setup on Windows hosts, implements the `git-build-readiness` command and `print_build_readiness.dart` script, and bumps the app version to v0.56.

If no trusted artifact exists after v0.56, the next milestone is:
**v0.57 Git arm64 Build Attempt**
