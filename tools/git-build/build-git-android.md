# Build Git For Android

Preferred long-term strategy: build Git from auditable source for Android
`arm64-v8a` using a reproducible project-controlled process.

v0.51 detects Android SDK/NDK `28.2.13676358`, the NDK arm64 compiler and make,
and SDK CMake. It does not build Git because the repository contains no trusted
Git source or dependency sources, Perl is missing from host `PATH`, and the
cross-build recipe has not completed review. The app must not download source
or binaries at runtime.

Run `dart tools/git-build/check_build_env.dart` for the current host report and
`dart tools/git-build/build_git_arm64.dart` for the non-destructive preflight.

v0.52 adds `build-inputs.example.json` plus source/dependency host checkers.
These define the acquisition gate but do not provide real inputs or enable a
compile. `build-inputs.json` must not exist until every placeholder is replaced
with reviewed metadata and source files.

Before a production artifact can be added, record:

- Git version
- source URL or source archive note
- source checksum
- license review
- dependency list and checksums
- Android NDK/toolchain version
- exact build commands
- expected payload file list
- `git --version` result on device
- `git-artifact production-status` and `git-artifact bundle-check` output

Until those exist, keep Git unavailable.
