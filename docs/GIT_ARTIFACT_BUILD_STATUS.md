# Git Artifact Build Status (v0.49)

## Current State

Termode v0.49 prepares the first production Git artifact path for Android
`arm64-v8a`, but does not include a real Git artifact.

- selected path: Path C, no real artifact yet
- real Git artifact: not present
- Git installed: no
- `runtime-pkg install git`: refuses safely
- `git-version`: does not fake output
- `git-exec-probe`: blocked until Git is installed
- beta readiness: unaffected by missing Git

## Strategy Decision

Path A, building Git from source for Android `arm64-v8a`, is the preferred
long-term trust path. It is not performed in v0.49 because this checkout does
not include Git source, dependency source archives, Android build scripts, or
recorded checksums for a reproducible source bundle.

Path B, a project-controlled vendored artifact, is not available because no
reviewed payload is present in the repository.

Path C is therefore the honest result: build the reproducible project-side
pipeline, keep templates/examples only, and keep Git unavailable until a
trusted artifact exists.

## Target

- tool: Git
- command: `git`
- Android ABI: `arm64-v8a`
- verification command: `git --version`
- workspace smoke plan: `git-workspace-smoke-plan`

## Required Before Git Can Ship

- Git version and source provenance
- source checksum or vendored artifact checksum
- dependency list and checksums
- license review
- reproducible build notes
- `manifest.json` under `tools/runtime-artifacts/git/arm64-v8a/`
- payload files under `tools/runtime-artifacts/git/arm64-v8a/files/`
- SHA-256 and byte count for every payload file
- successful `git-artifact bundle-check`
- successful `runtime-pkg install git`
- successful real `git --version` on Android

## Why Git Remains Unavailable

Termode must not fake Git or execute untrusted binaries. Without a trusted
payload, the correct behavior is:

```sh
git-artifact bundle-status
git-artifact bundle-check
runtime-pkg install git
git-version
git-exec-probe
```

These commands report the missing artifact and point to the production build
pipeline.

Next milestone if no trusted artifact exists: v0.50 Git Artifact Production /
Trusted Build.
