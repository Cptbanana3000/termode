# Git Executable Storage Strategy

## Selected strategy: `native-library-dir`

The Git manifest's logical path and Android's physical executable path serve
different purposes:

| Role | Path |
| --- | --- |
| Stable Termode command | `TERMODE_PREFIX/usr/bin/git` |
| Manifest artifact | `tools/runtime-artifacts/git/arm64-v8a/files/usr/bin/git` |
| APK native entry | `lib/arm64-v8a/libtermode_git_exec.so` |
| Runtime backing | `applicationInfo.nativeLibraryDir/libtermode_git_exec.so` |

The logical prefix entry maps to the immutable runtime backing. Termode stores
both paths in package metadata and reports them through `bin-which git`.
`runtime-pkg verify git` rechecks the mapping, exact backing path, ELF magic,
byte count, SHA-256, and a real execution probe.

This strategy was selected because it uses Android's supported executable
packaging path, works without root or external storage, keeps the artifact
immutable, and preserves the existing Termode prefix abstraction. Writable
copy execution, arbitrary shell indirection, and shared-storage execution are
not fallback strategies.
