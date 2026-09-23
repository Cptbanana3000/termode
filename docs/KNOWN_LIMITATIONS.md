# Known Limitations & Capabilities Matrix

Termode is in active developer beta (Milestone v0.79). This document provides an accurate, transparent overview of current capabilities, verified engines, and deliberate technical constraints.

---

## 1. Verified Native Engines & Runtimes (ARM64-v8a)

Termode enforces an **anti-mocking rule** (GEMINI.md Rule 1): all supported runtimes are authentic, upstream binaries executing directly on hardware:

| Runtime / Engine | Upstream Version | Execution Mode | Verification Status |
| :--- | :--- | :--- | :--- |
| **CPython** | v3.14.6 | Native ELF executable in `nativeLibraryDir` | Fully verified on hardware; interactive REPL, scripts, sockets, HTTPS |
| **pip** | v26.2.1 | Upstream wheel extracted into site-packages | Fully verified; live PyPI downloads, SSL verification, `--user` installs |
| **Node.js** | v24.18.0 | Native ELF executable with V8 engine | Fully verified; interactive REPL, scripts, standard library |
| **Git** | v2.44.0 | Native ELF executable in `nativeLibraryDir` | Local-only verified (`init`, `status`, `add`, `commit`, `branch`, `log`) |
| **Dev Server** | Termode Daemon | Process supervision with log rotation | Verified; background process management, port binding |
| **OSINT** | Sherlock v0.16.2 | Pure-Python engine with 480+ targets | Fully verified on physical hardware |

---

## 2. Android Security & Execution Constraints (W^X / SELinux)

### Writable Storage `noexec`
Android 10+ (API 29+) enforces Write XOR Execute (`noexec`) on all app-writable directories (`/data/user/0/...`).
- **Impact**: Shell scripts or executables installed by `pip` into `$HOME/.local/bin/` or `npm` into `$HOME/.npm-global/bin/` cannot be directly executed via `execve` by `/system/bin/sh`.
- **Termode DX Hardening**: Termode automatically scans `$HOME/.local/bin/` and `$HOME/.npm-global/bin/` to generate compliant shell wrapper functions in `$TERMODE_USR/termode-shell-helpers.sh`. Bare commands (e.g. `cowsay`, `pyfiglet`, `black`) run through their parent native binary without `Permission denied`.

---

## 3. Python Ecosystem & C-Extensions

- **Pure-Python Packages**: Packages composed entirely of Python code (e.g. `requests`, `urllib3`, `rich`, `click`, `cowsay`, `pyfiglet`, `black`, `flake8`, `jinja2`) install and run seamlessly via `pip install --user <pkg>`.
- **Compiled C Extensions**: Android uses Google's Bionic libc rather than GNU glibc. Packages requiring compilation during installation (or standard manylinux wheels with compiled C extensions, such as `numpy` or `cryptography`) cannot be built on-device without an Android NDK toolchain and cross-compiled Bionic wheels.

---

## 4. Git Capabilities & Deferrals

- **Supported (Local Version Control)**:
  - Repository initialization (`git init`)
  - Status queries (`git status`)
  - Staging and committing (`git add`, `git commit`)
  - Branching and checkout (`git branch`, `git checkout`)
  - History log inspection (`git log`)
- **Deferred (Network Transports)**:
  - Remote Git network transports (`git push`, `git fetch`, `git clone` over SSH/HTTPS) require integration with OpenSSL/libcurl network libraries, which is actively in development.

---

## 5. Storage & Sandboxing

- Termode executes within an isolated application sandbox.
- Access to external Android tablet storage (Downloads, Documents, external SD cards) requires linking via Android's Storage Access Framework (`storage-link`).
