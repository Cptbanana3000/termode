# Git arm64-v8a Artifact Pipeline (v0.49)

This document defines the project-side pipeline for producing a trusted Git
artifact for Android `arm64-v8a`.

## Artifact State

No real Git artifact exists in v0.49. The repository contains templates,
examples, helper docs, and validation scripts only.

## Layout

```text
tools/runtime-artifacts/git/
  README.md
  manifest.template.json
  arm64-v8a/
    README.md
    PLACE_ARTIFACT_HERE.txt
    manifest.json.example
    manifest.json        # only when a real trusted artifact exists
    files/
      README.md
      bin/git            # only when a real trusted artifact exists
  checksums/
    README.md
```

Do not create `manifest.json` for placeholders. A manifest with missing files
is intentionally `INVALID`.

## Manifest Requirements

The production manifest must include:

- `name: git`
- `kind: native-tool`
- `abi: arm64-v8a`
- `command: git`
- safe relative `entrypoint`, usually `bin/git`
- `files` with safe relative paths
- SHA-256 for every file
- positive byte count for every file
- `source: termode-built` or `termode-vendored`
- `source_url` or `source_note`
- `build_method`
- `license`
- `trusted_by`
- `verification_command: git --version`
- `smoke_tests`

Unsafe paths, parent traversal, absolute paths, placeholder checksums, zero byte
entries, unsupported ABIs, and untrusted sources are rejected.

## Helper Scripts

Optional project-side helpers live under `tools/git-build/`:

```sh
dart tools/git-build/hash_artifact.dart <file>
dart tools/git-build/prepare_manifest.dart arm64-v8a
dart tools/git-build/validate_git_artifact.dart arm64-v8a
```

The helpers do not download, install, or trust Git. They only hash or validate
files already staged by the project.

## Bundle Check

After staging a real artifact:

```sh
git-artifact bundle-check
```

Expected with no artifact:

```text
Overall: TEMPLATE_ONLY
```

or:

```text
Overall: UNAVAILABLE
```

Expected with a valid artifact:

```text
Overall: AVAILABLE
```

## Install / Smoke Gate

Only after `bundle-check` is `AVAILABLE`:

```sh
runtime-pkg install git
git-version
git-exec-probe
git-smoke-test
runtime-pkg verify git
git-doctor
```

The installer must validate the manifest, verify hashes, copy only
manifest-owned files into `TERMODE_PREFIX`, run `git --version`, and mark Git
installed only after the real version command succeeds. Failures roll back
copied files.

## Workspace Smoke Plan

Do not run workspace mutation automatically. When real Git is installed, run:

```sh
git-workspace-smoke-plan
```

Then execute the printed commands manually on device.
