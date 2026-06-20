# Git Source Acquisition

Termode needs auditable source because a native Git binary executes inside the
application sandbox and becomes part of the trusted runtime prefix. A random
binary cannot establish its source, patches, ABI, dependencies, license, or
security properties.

## Acceptable Source Forms

- a project-controlled Git source archive
- a reviewed project-controlled Git source tree
- a verified upstream source archive whose SHA-256 is recorded

## Rejected Source Forms

- random zip files or binaries
- binaries extracted from an APK
- copied Termux files without complete provenance
- unverified mirrors
- downloads performed by the Android app
- silent downloads performed by host scripts
- arbitrary user-provided archives

## Required Metadata

Every Git source record must include:

- Git version
- source type and safe project-relative path
- upstream URL or auditable source note
- license (`GPL-2.0-only` for Git)
- SHA-256 checksum
- acquisition date
- `trusted_by` reviewer/project identity
- reproducible build method

Place reviewed inputs under `tools/git-build/sources/`. Create
`tools/git-build/build-inputs.json` from the example only after replacing every
placeholder and setting `template_only` to false or removing it.

## Verification

```sh
dart tools/git-build/check_build_inputs.dart
dart tools/git-build/verify_git_source.dart
dart tools/git-build/check_dependencies.dart
```

Paths must remain under project-controlled source/dependency roots. Archives
must exist and match their recorded SHA-256. Source trees must exist and retain
an archive/commit provenance checksum record.

## Minimum First Target

The first real artifact proves only:

- `git --version`
- `git init`
- `git status`

Local add/commit/log follows after that proof. HTTPS clone/fetch/pull/push,
credentials, SSH, LFS, submodules, and advanced hooks are not part of the first
target.
