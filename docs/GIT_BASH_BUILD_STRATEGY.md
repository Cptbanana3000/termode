# Git Bash Build Strategy - Termode v0.60

This document outlines how Git Bash is leveraged on the Windows host to execute POSIX/Unix shell steps for compiling Git (arm64-v8a) using the Android NDK.

## The Shell Challenge
Git's Makefile relies heavily on standard Unix utilities (like `sh`, `uname`, `sed`, `grep`, and others) for script configuration and directory structure operations. Standard Windows Command Prompt (`cmd.exe`) and PowerShell do not native map to these commands, leading to syntax and environment errors during execution.

## Path A: Git Bash Strategy
Termode v0.60 selects **Path A (Git Bash is viable)** as its host orchestration strategy:
1. **Host-Side Execution**: PowerShell orchestrates the overall build, but calls Git Bash to handle POSIX-compatible commands.
2. **Path Translation**: Backslashes are translated to forward slashes, and drive letters (e.g. `C:\`) are converted to POSIX format (e.g. `/c/`). Paths containing spaces are quoted safely.
3. **Android NDK Path Alignment**: NDK compiler executables and build inputs are formatted to be invoked directly from Git Bash, allowing clean cross-compilation.

## Preflight Verification Checklist
Before starting a build attempt, the host verifies the following prerequisites via `tools/git-build/git_bash_preflight.dart`:
- Git Bash is located at a standard candidate path or via user environment.
- POSIX utilities (`uname`, `sed`, `sh`, `perl`, `bash`) respond correctly within the Bash context.
- Staged Git and zlib outputs are accessible from Git Bash.
- Android NDK cross-compilers can run and return their versions inside the Git Bash environment.

Only when all preflight checks report **READY** will a real compilation step be permitted in subsequent milestones.
