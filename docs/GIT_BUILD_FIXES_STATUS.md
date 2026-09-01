# Git Build Fixes Status (v0.59)

Termode version v0.59 selects **Path C: Windows-native Git build is not practical without a Unix-like build shell** as its final build status.

## Status Overview
* **Selected Path**: Path C (prerequisites checked; zlib output reusable/verified; Git build fails due to Unix-like shell requirements in the Makefile)
* **zlib status**: VERIFIED (static library present at `tools/git-build/output/arm64-v8a/zlib/lib/libz.a`)
* **Git build status**: FAILED (Make build cannot proceed without POSIX utilities)
* **Failure Category**: `Windows shell/path issue` (Makefile requires `/bin/sh`, `sed`, `uname`)

## Log & Failure Diagnosis
The build logs show:
* `CreateProcess(NULL, sh -c "uname -s 2>/dev/null || echo not", ...) failed`
* `make: *** [Makefile:3092: GIT-CFLAGS] Error 1`

The Git compilation cannot proceed natively on a standard Windows Command Prompt or PowerShell because the Makefile relies on shell expansion and shell shims.

## Recommended Build Host Strategy
To successfully compile Git for Android arm64-v8a, we recommend one of the following POSIX-like build shell strategies on the host:
1. **MSYS2 / Git Bash**: Run the build script within an MSYS2 or Git Bash shell environment where `/bin/sh`, `sed`, and `uname` are available on the PATH, while keeping NDK compiler paths correctly set.
2. **WSL (Windows Subsystem for Linux)**: Perform the cross-compilation within a WSL Ubuntu environment where the Android NDK for Linux is installed.
3. **Dedicated Linux Build Host**: Build the artifact on a Linux machine or CI runner using the Linux NDK.

Do not install any software automatically. This decision must remain controlled and user-configured.

## Next Milestone
**v0.60 Git Build Host Strategy**
The next milestone will focus on defining and documenting the verified Unix-like build shell execution pathway.
