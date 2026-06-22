# Git arm64 Build Logs (v0.58)

This document describes the location, contents, and analysis of the build logs captured during the first controlled Git arm64 build attempt.

## Log Locations
All build logs are saved in the project repository under:
`tools/git-build/logs/`

1. **zlib Build Logs**:
   * **Path**: `tools/git-build/logs/zlib-arm64-build.log`
   * **Contents**: Captures stdout/stderr of the CMake configuration and build steps.
   * **Result**: Compilation was successful, producing a verified `libz.a` static library.
2. **Git Build Logs**:
   * **Path**: `tools/git-build/logs/git-arm64-build.log`
   * **Contents**: Captures stdout/stderr of the NDK `make` invocation.
   * **Result**: FAILED (exit code 1).

## Failure Analysis
The compiler/make logs for Git show that the build failed under:
* **Failure Category**: `Windows shell/path issue`
* **Root Cause**: The Git build system relies on shell scripting (like `/bin/sh`) to determine options, build versions, and map directories. When run natively on a Windows command environment, the NDK `make.exe` is unable to launch `/bin/sh` or execute Unix-style shell syntax.

## Reviewing Logs
Developers can review the full host build attempt output directly in the log files.
From the command prompt:
```powershell
Get-Content tools/git-build/logs/git-arm64-build.log -Tail 50
```
or by opening the logs in an editor.
