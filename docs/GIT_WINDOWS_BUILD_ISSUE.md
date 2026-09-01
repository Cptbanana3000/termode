# Git Windows Build Issue (v0.59)

This document provides a detailed technical explanation of why building Git 2.44.0 natively on a Windows host using standard CMD/PowerShell is not practical, and how Unix-like environments resolve this.

## Root Cause Analysis
The Git compilation relies on its Unix-style `Makefile`. When NDK `make` is invoked, it attempts to execute multiple shell sub-processes. This includes:
1. **Version Generation (`GIT-VERSION-GEN`)**:
   Runs `/bin/sh ./GIT-VERSION-GEN` to evaluate the repository version and generate `GIT-VERSION-FILE`. Under Windows native shells, `sh` is missing or is not recognized, causing the process to fail.
2. **Platform Flags (`GIT-CFLAGS`)**:
   Make compiles compilation flags dynamically by piping options through POSIX utilities like `sed`, `uname`, and `curl-config`. Windows native command processors do not parse Unix pipelines or recognize these tools, causing errors like:
   * `CreateProcess(NULL, sh -c "uname -s 2>/dev/null || echo not", ...) failed`
   * `make: *** [Makefile:3092: GIT-CFLAGS] Error 1`

## POSIX Shell Simulation Requirements
A successful build requires routing Make shell commands through a shell emulator that supports:
* POSIX shell scripting (`sh`, `bash`).
* Unix path expansion (mapping `/bin/sh` and resolving absolute compiler sysroots).
* POSIX utilities: `sed`, `uname`, `tr`, `grep`, `mkdir -p`.

## Supported Solutions
To compile Git for Android arm64-v8a, developers should use one of these environments:
1. **MSYS2**:
   Provides a full POSIX-like package ecosystem on Windows. Developers run the build script from the MSYS2 MinGW or MSYS terminal.
2. **Git Bash**:
   A lightweight shell emulator packaged with Git for Windows. Running `bash tools/git-build/...` allows the Makefile to locate `sh` and basic tools.
3. **WSL**:
   Runs a native Linux kernel under Windows. Cross-compiling in WSL using the Linux NDK avoids Windows path/shell translation issues entirely.
