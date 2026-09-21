# Git Runtime Artifact Manifest - v0.63

## v0.64 execution fields

The promoted manifest now records `logical_install_path: usr/bin/git`,
`executable_strategy: native-library-dir`,
`executable_package_name: libtermode_git_exec.so`, matching original and
packaged executable hashes, the execution-policy note, `local_only: true`,
and `remote_features_deferred: true`. The registry rejects unknown strategies,
unsafe names, mismatched hashes, or a milestone other than v0.64.

The Git manifest is a trust boundary, not a download recipe. It records the
Git/zlib source hashes, exact ELF hash and byte count, arm64-v8a ABI,
minimal-local build mode, reviewer identity, and supported/deferred features.

The registry accepts the payload only when template_only and candidate are
both false, the source is termode-built, every relative path remains beneath
the artifact files directory, and bytes/checksums match. The Git entry must
also start with ELF magic; scripts and placeholders are rejected.

`usr/bin/git` is the artifact's logical install target. It maps to the exact
approved file in `applicationInfo.nativeLibraryDir`; the writable prefix does
not receive a copied executable.
