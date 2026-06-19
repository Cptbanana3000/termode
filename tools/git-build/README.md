# Git Build Helpers

This folder documents the project-side Git artifact production pipeline for
Termode. Nothing here runs inside the Android app, downloads files, or installs
Git automatically.

Current v0.50 result:

- target ABI: `arm64-v8a`
- selected path: Path B, trusted production pipeline completed but no real artifact yet
- trusted artifact state: unavailable
- app behavior: `runtime-pkg install git` refuses safely

Read:

- `build-git-android.md`
- `artifact-layout.md`
- `verify-artifact.md`
- `manifest.schema.example.json`

Optional Dart helpers can be run from the project root to inspect a staged
candidate, but they do not produce or trust a Git binary by themselves.

```sh
dart tools/git-build/hash_git_artifact.dart <file>
dart tools/git-build/prepare_git_artifact.dart arm64-v8a
dart tools/git-build/validate_git_artifact.dart arm64-v8a
```
