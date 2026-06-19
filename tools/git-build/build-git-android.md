# Build Git For Android

Preferred long-term strategy: build Git from auditable source for Android
`arm64-v8a` using a reproducible project-controlled process.

v0.50 does not build Git because the repository does not contain Git source,
dependency source archives, Android build scripts, or recorded checksums for a
trusted source bundle. The app must not download source or binaries at runtime.

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
