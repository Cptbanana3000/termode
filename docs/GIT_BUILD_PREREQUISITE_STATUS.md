# Git Build Prerequisite Status (v0.56)

Termode version v0.56 selects **Path B: Partial prerequisite progress** (sources staged, Perl missing, readiness checked).

## Current Host Status
- **Perl**: Missing. Perl is required on the host to generate header files during the Git NDK build.
- **Git source**: Staged (`tools/git-build/sources/git-2.44.0.tar.xz`). Checksum matched.
- **zlib source**: Staged (`tools/git-build/sources/zlib-1.3.1.tar.xz`). Checksum matched.
- **build-inputs.json**: Promoted (present and verified).
- **Git artifact**: Unavailable.
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
