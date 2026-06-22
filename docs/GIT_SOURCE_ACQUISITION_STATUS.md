# Git Source Acquisition Status (v0.53)

## Selected Path

Termode v0.53 selects **Path B: toolchain available, preparation incomplete**.

Available from the v0.51-v0.52 host check:

- Android SDK and NDK `28.2.13676358`
- arm64-v8a LLVM compiler
- NDK make and SDK CMake
- archive tool and writable output directory

Still missing:

- Perl on the host `PATH`
- reviewed Git source archive or source tree (version 2.44.0 chosen)
- reviewed zlib/dependency sources (minimal strategy defined)
- real `tools/git-build/build-inputs.json`
- arm64-v8a Git artifact

The checked-in `build-inputs.example.json` is marked `template_only: true`. It
contains placeholder metadata and an all-zero checksum, so the host validator
must never treat it as build-ready.

## Host Checker Results

```text
check_build_inputs.dart: PARTIAL (input manifest/source/dependencies/Perl missing)
verify_git_source.dart: NOT READY (source metadata missing)
check_dependencies.dart: PLANNED (zlib and later dependencies not configured)
```

No checker downloads, builds, executes, installs, or creates an artifact.

## Runtime Result

Git remains unavailable and not installed. `runtime-pkg install git` refuses
safely, `git-version` never fakes output, and missing build inputs do not block
Termode beta readiness.

## Next

**v0.54 Git Build Prerequisite Resolution**

Provide reviewed source inputs, record checksums/provenance in a real
`build-inputs.json`, install/locate Perl, and rerun all host checkers.
