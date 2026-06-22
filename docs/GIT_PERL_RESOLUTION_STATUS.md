# Git Perl Resolution Status (v0.57)

Termode version v0.57 selects **Path B: Perl still missing but setup guidance/checkers are improved**.

## Current Host Status
- **Perl**: Missing. Perl is required on the host to generate header files during the Git NDK build.
- **Git source**: Staged (`tools/git-build/sources/git-2.44.0.tar.xz`). Checksum matched.
- **zlib source**: Staged (`tools/git-build/sources/zlib-1.3.1.tar.xz`). Checksum matched.
- **build-inputs.json**: Promoted (present and verified).
- **NDK and compiler**: Available.
- **Git artifact**: Unavailable.
- **Git installation**: Refused safely.

## Resolution Plan & Staged Status
We have improved host-side Perl detection and setup guidance. Since Perl remains missing from the host environment, the build pipeline status is **PARTIAL**. 

A new documentation guide `docs/GIT_PERL_SETUP_WINDOWS.md` has been added to assist in manually installing Perl on Windows hosts.

Once Perl is configured on the host PATH, rerun `dart tools/git-build/check_build_env.dart` or `dart tools/git-build/print_build_readiness.dart`.
