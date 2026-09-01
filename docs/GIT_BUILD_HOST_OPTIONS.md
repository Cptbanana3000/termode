# Git Build Host Options - Termode v0.60

This document compares different host environment strategies considered for building the arm64 Git executable for Termode on a Windows host.

| Feature / Criteria | Path A: Git Bash (Selected) | Path B: MSYS2 | Path C: WSL |
| :--- | :--- | :--- | :--- |
| **Availability** | Extremely high (installed with Git for Windows). | Requires manual setup and installation of MSYS2 environments. | Requires WSL features enabled and a Linux distro installed. |
| **Path Structure** | Windows native paths mapped to `/c/`, `/d/` mount styles. | Custom mount formatting, requires `/mingw64` or `/usr` prefixes. | Linux standard paths via `/mnt/c/`, `/mnt/d/` style mounts. |
| **Compiler Invocation** | Invokes standard Windows NDK cross-compilers directly. | Invokes Windows NDK compilers, but compiler shell escaping can conflict. | Must invoke NDK compilers (either Linux NDK or Windows NDK cross-builds). |
| **Dependencies** | Uses host Perl/make directly. | Uses MSYS2 package manager dependencies. | Uses native Linux dependencies (e.g. `apt install perl make`). |
| **Complexity** | Low (simple path translation helper, minimal config). | Medium (requires maintaining MSYS2 environment state). | High (requires syncing files or path sharing across Linux/Windows). |

## Selected Strategy: Git Bash (Path A)
Since Git Bash is found by default on developer machines and provides standard POSIX tools (`sh`, `uname`, `sed`) along with direct access to Windows paths, it is selected as the primary driver for our POSIX Makefile build integration in v0.60.
