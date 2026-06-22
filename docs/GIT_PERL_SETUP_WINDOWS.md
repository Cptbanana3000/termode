# Git Perl Setup on Windows

Perl is required on the host environment to run the NDK compilation scripts for building Git.

## Core Concepts
1. **Host-Side Only**: Perl is only used on your development machine (the host) at build time. It is **not** bundled into the Android application and is not executed on the mobile device.
2. **Why Perl is Needed**: Git's build configuration and source generation scripts (e.g., generating header files or parser code) rely on a Perl interpreter.
3. **Missing Perl is Not an App Failure**: If Perl is missing, the Termode Android application will still run perfectly in beta. However, the host cannot compile a new Git binary artifact.

## Installation Options on Windows
You can manually install any trusted Perl distribution. Recommended options include:

### Option 1: Strawberry Perl (Recommended)
Strawberry Perl is a 100% open-source Perl environment for MS Windows containing everything you need to compile and use Perl.
1. Download the installer from the official website: [https://strawberryperl.com/](https://strawberryperl.com/)
2. Run the installer and follow the prompt instructions.

### Option 2: ActiveState Perl
ActiveState Perl is a popular commercial Perl distribution with free options for community use.
1. Sign up/install via State Tool or download installer from [https://www.activestate.com/](https://www.activestate.com/)

## Post-Installation Steps
1. **Restart Your Terminal**: After installation, close and reopen your terminal or IDE (e.g. VS Code, PowerShell) to ensure environment variables are refreshed.
2. **Verify Perl on PATH**: Run the following command on the host:
   ```cmd
   perl --version
   ```
   If successful, it should output version information (e.g., `This is perl 5, version 38...`).
3. **Rerun Host Environment Checkers**: Once Perl is verified, run:
   ```cmd
   dart tools/git-build/check_build_env.dart
   ```
   Or check the full build readiness status:
   ```cmd
   dart tools/git-build/print_build_readiness.dart
   ```

## Linux and macOS Users
For non-Windows users, Perl is usually pre-installed on the system or can be installed via your system package manager:
- **macOS**: `brew install perl` (if not present)
- **Ubuntu/Debian**: `sudo apt-get install perl`
- **Fedora/CentOS**: `sudo dnf install perl`
