# Git Artifact Production Status (v0.50)

## Selected Path

Termode v0.50 selects **Path B: reproducible build pipeline completed, no
artifact yet**.

No real trusted Git artifact is present in this repository or bundled APK. Git
therefore remains unavailable, `runtime-pkg install git` refuses safely, and no
Termode command fakes `git --version`.

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

- audited Git source archives with checksums
- vendored dependency source archives with checksums
- a reproducible Android Git build output
- a reviewed `arm64-v8a` payload under `tools/runtime-artifacts/git/arm64-v8a/files/`
- a real installable `manifest.json`
- a successful Android `git --version` proof

Because Termode must not fake Git or execute unknown binaries, the correct
state is to ship the production pipeline and keep Git unavailable.

## Production Gate

Git can be marked available only after all of these pass:

1. real trusted payload staged under `tools/runtime-artifacts/git/arm64-v8a/files/`
2. manifest generated with safe relative paths, SHA-256 hashes, and byte counts
3. `git-artifact bundle-check` reports `AVAILABLE`
4. `runtime-pkg install git` succeeds
5. `git-version` prints a real Git version
6. `git-smoke-test` reports `HEALTHY`
7. workspace smoke commands are manually run on Android

## Next Milestone

If no trusted artifact exists after v0.50, the next milestone is:

**v0.51 Git Artifact Payload Build / Device Verification**

