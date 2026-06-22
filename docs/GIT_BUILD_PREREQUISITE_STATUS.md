# Git Build Prerequisite Status (v0.58)

Termode version v0.58 selects **Path B: Build attempt starts but fails** (prerequisites ready; build attempted; zlib succeeded; Git make failed).

## Current Host Status
- **Perl**: READY (v5.42.2 found on host).
- **Git source**: Staged (`tools/git-build/sources/git-2.44.0.tar.xz`). Checksum matched.
- **zlib source**: Staged and compiled (`libz.a` static library produced at `tools/git-build/output/arm64-v8a/zlib/lib/libz.a`).
- **build-inputs.json**: Promoted (present and verified).
- **Git artifact**: Unavailable (make build failed).
- **Git installation**: Refused safely.

## Progress in v0.55
- Staged official `git-2.44.0.tar.xz` source archive under `tools/git-build/sources/`.
- Staged official `zlib-1.3.1.tar.xz` dependency archive under `tools/git-build/sources/`.
- Promoted the manifest to a production `build-inputs.json` mapping the staged archives and their verified target SHA-256 checksums.
- Updated host checks and regex validations to accept staged archives and paths under `tools/git-build/sources/` for both git and dependencies.
- Verified that all checksum verification scripts run successfully and report matches for staged files.

## Progress in v0.56
- Hardened host-side Perl detection in `check_build_env.dart` and `check_build_inputs.dart`.
- Created `print_build_readiness.dart` to summarize host readiness.
- Implemented manual Windows setup guidance in `docs/GIT_PERL_SETUP_WINDOWS.md` and registered `docs/GIT_PERL_RESOLUTION_STATUS.md`.
- Added the `git-build-readiness` command to the terminal catalog and real PTY interception, and bumped versions across the project.

## Progress in v0.57
- Finalized host-side Perl prerequisite checking, error handling, and manual setup docs.
- Selected Path B (Perl still missing on the Windows host) and documented the final status.
- Bumped all in-app diagnostics commands, docs, and version configurations to v0.57.

## Progress in v0.58
- Perl setup follow-up completed: Strawberry Perl v5.42.2 detected on host, with fallback paths added to `check_build_env.dart` for robust detection.
- Successfully cross-compiled zlib 1.3.1 using NDK toolchain and CMake, outputting `libz.a` under `tools/git-build/output/arm64-v8a/zlib/`.
- Attempted Git 2.44.0 cross-compilation using NDK compiler and Makefile, failing honestly due to Windows shell/path limitations.
- Captured build attempt logs under `tools/git-build/logs/git-arm64-build.log` and classified the failure honestly.
