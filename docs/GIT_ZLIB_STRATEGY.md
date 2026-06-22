# Git zlib Strategy (v0.57)

This document details the strategy for acquiring, reviewing, and staging **zlib** as the primary dependency for building Git on Android.

## Selected Dependency Version
- **Name**: zlib
- **Version**: `1.3.1`
- **License**: zlib License
- **Upstream URL**: `https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.xz`
- **SHA-256 Checksum**: `38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32` (verified official release)

## Role in Git
zlib is required by Git to compress and decompress packfiles, objects, and loose database entries. For our Stage 1 minimal local Git build, zlib is the only runtime dependency we need to compile and link against.

## Staging Rules
1. **Source Archive**: Must be downloaded from the official upstream link and staged locally under `tools/git-build/sources/zlib-1.3.1.tar.xz`.
2. **Path Security**: Build tools must only access files within the designated `tools/git-build/sources/` subdirectory to avoid path traversal.
3. **Verification**: The check scripts will verify that the staged zlib archive matches the recorded SHA-256 checksum exactly before compilation starts.
4. **App Delivery**: The zlib library will be statically compiled into the Git executable or loaded as a shared library (`libz.so`) from the system. On Android, the NDK provides a system `libz.so`, but static linking against our staged zlib-1.3.1 is preferred to ensure behavior consistency and absolute platform independence.
