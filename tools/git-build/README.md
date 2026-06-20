# Git Build Helpers

This folder documents the project-side Git artifact production pipeline for
Termode. Nothing here runs inside the Android app, downloads files, or installs
Git automatically.

Current v0.52 result:

- target ABI: `arm64-v8a`
- selected path: Path B, SDK/NDK present but Perl and trusted inputs missing
- trusted artifact state: unavailable
- app behavior: `runtime-pkg install git` refuses safely

Read:

- `build-git-android.md`
- `artifact-layout.md`
- `verify-artifact.md`
- `manifest.schema.example.json`
- `check_build_env.dart`
- `build_git_arm64.dart`
- `build-inputs.example.json` and `build-inputs.schema.example.json`
- `check_build_inputs.dart`, `verify_git_source.dart`, `check_dependencies.dart`

Optional Dart helpers can be run from the project root to inspect a staged
candidate, but they do not produce or trust a Git binary by themselves.

```sh
dart tools/git-build/check_build_env.dart
dart tools/git-build/check_build_inputs.dart
dart tools/git-build/verify_git_source.dart
dart tools/git-build/check_dependencies.dart
dart tools/git-build/build_git_arm64.dart
dart tools/git-build/hash_git_artifact.dart <file>
dart tools/git-build/prepare_git_artifact.dart arm64-v8a
dart tools/git-build/validate_git_artifact.dart arm64-v8a
```
