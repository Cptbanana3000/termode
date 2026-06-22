# Git Source Acquisition (v0.56)

Termode needs auditable source because a native Git binary executes inside the application sandbox and becomes part of the trusted runtime prefix. A random binary cannot establish its source, patches, ABI, dependencies, license, or security properties.

## Acceptable Source Forms
- A verified upstream source archive whose SHA-256 is recorded.
- A reviewed project-controlled Git source tree with a provenance note.
- A project-controlled Git source archive.

## Rejected Source Forms
- Random zip files or binaries.
- Binaries extracted from an APK.
- Copied Termux files without complete provenance.
- Unverified mirrors.
- Downloads performed by the Android app.
- Silent downloads performed by host scripts.
- Arbitrary user-provided archives.

## Required Metadata
Every Git source record must include:
- Git version (pinned to `2.44.0` in v0.56).
- Source type and safe project-relative path.
- Upstream URL or auditable source note.
- License (`GPL-2.0-only` for Git).
- SHA-256 checksum.
- Acquisition date.
- `trusted_by` reviewer/project identity.
- Reproducible build method.

Place reviewed inputs under `tools/git-build/sources/`. Create `tools/git-build/build-inputs.json` from the candidate manifest or example only after replacing every placeholder and setting `template_only` to false and removing `candidate: true`.

## Verification
```sh
dart tools/git-build/check_build_inputs.dart
dart tools/git-build/verify_git_source.dart
dart tools/git-build/check_dependencies.dart
```

Paths must remain under project-controlled source/dependency roots. Archives must exist and match their recorded SHA-256. Source trees must exist and retain an archive/commit provenance checksum record.

## Minimum First Target
The first real artifact proves only:
- `git --version`
- `git init`
- `git status`

Local add/commit/log follows after that proof. HTTPS clone/fetch/pull/push, credentials, SSH, LFS, submodules, and advanced hooks are not part of the first target.
