# Git Perl Requirement (v0.57)

This document describes the role of Perl as a build-time dependency for compiling Git.

## Role of Perl
- **Host-Side Build Prerequisite**: Perl is required on the host system to execute Git's internal build scripts, configure scripts, and generate makefiles during cross-compilation.
- **Not Bundled in App**: Perl is **not** packaged, installed, or bundled in the Termode Android application. It is strictly a build-time requirement.
- **Blocks Git Build**: Yes. Without Perl on the host, compiling Git from source is blocked.
- **Blocks Termode Beta**: No. A missing Perl environment on the developer's host does not impact the Termode application execution or Beta readiness.

## How to Resolve on Host
Termode does not download or install Perl itself. You must configure Perl manually on the host machine:
- **Windows**: Use a trusted Perl distribution. See [Git Perl Setup on Windows](GIT_PERL_SETUP_WINDOWS.md) for detailed configuration steps.
- **Linux/macOS**: Use the system package manager (`sudo apt install perl` or `brew install perl`) or use the existing Perl interpreter if already available.

Verify the installation by running:
```sh
perl --version
```

## How the Build Checker Detects It
The host detector script [check_build_env.dart](file:///d:/Projects/termode/tools/git-build/check_build_env.dart) attempts to locate the Perl executable on the host's `PATH`.
- Output: `Perl: <version summary or missing>`
- Role: host build prerequisite
- Blocks Git build: yes/no
- Blocks Termode beta: no
