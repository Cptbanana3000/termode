# Python Environment Architecture & arm64 Prototype

## Executive Summary
Milestone **v0.74** establishes the official architecture, filesystem hierarchy, environment isolation, diagnostic tooling, and command dispatch for the authentic Python (CPython) runtime ecosystem in Termode, targeting Android ARM64 (`arm64-v8a`).

In strict compliance with [`GEMINI.md`](../GEMINI.md):
- **Zero Mocking / Fake Runtimes**: We strictly prohibit mock interpreters or fake output. Before authentic binary acquisition, Termode's diagnostic tooling (`python-doctor`, `python-env`) honestly reports exact prototype status, target ABI, and missing components.
- **W^X Security Compliance (Android 10+)**: Android SELinux enforces Write XOR Execute (`noexec`) on writable storage (`/data/user/0/com.termode.termode/files/`). Executable native Python binaries are architected to reside in `applicationInfo.nativeLibraryDir` as `libtermode_python_exec.so` or invoked through compliant native bridges.
- **Target Benchmark**: Enables real-world Python OSINT CLI tools (**Sherlock** and **Maigret**) installed via `pip install --user` with zero external app dependencies (no Termux required).

---

## 1. Directory & Path Hierarchy

Termode unifies Python's user-site and standard prefix within its secure sandbox:

```
/data/user/0/com.termode.termode/files/
├── usr/                                 <-- TERMODE_PREFIX ($PYTHONHOME)
│   ├── bin/
│   │   ├── python3                      <-- CLI Wrapper / Entrypoint
│   │   └── pip3                         <-- Pip Package Manager Entrypoint (v0.75+)
│   └── lib/
│       └── python3.11/                  <-- CPython 3.11 Standard Library
│           ├── os.py
│           ├── sys.py
│           ├── asyncio/
│           ├── ssl.py
│           └── lib-dynload/             <-- Compiled C-extension modules (.so)
│
└── home/                                <-- TERMODE_HOME ($HOME)
    └── .local/                          <-- PYTHONUSERBASE
        ├── bin/                         <-- Pip Executables (sherlock, maigret, black) [IN PATH]
        └── lib/
            └── python3.11/
                └── site-packages/       <-- User-installed PyPI packages
```

---

## 2. Environment Variables & PATH Propagation

Every REAL PTY shell session, Dart execution context, and shell script automatically receives sanitized Python environment variables:

| Variable | Value | Purpose |
|---|---|---|
| **`PATH`** | `...:$HOME/.local/bin:...` | Guaranteed execution of pip-installed CLI tools without specifying path |
| **`PYTHONUSERBASE`** | `$HOME/.local` | Directs `pip install --user` to Termode's sandboxed local directory |
| **`PYTHONHOME`** | `$TERMODE_PREFIX/usr` | Directs CPython to the bundled standard library |
| **`PYTHONPATH`** | `$PREFIX/usr/lib/python3.11:$HOME/.local/lib/python3.11/site-packages` | Guarantees module resolution across stdlib and user packages |
| **`LD_LIBRARY_PATH`** | `$PREFIX/usr/lib:$NATIVE_LIB_DIR` | Resolves Bionic shared libraries (`libssl.so`, `libcrypto.so`, `libsqlite3.so`) |

---

## 3. Native Bionic Dependencies (arm64-v8a)

CPython on Android requires linkage against Android Bionic libc and core C libraries:
* **`libc.so`**, **`libm.so`**, **`libdl.so`**: Android Bionic standard C/Math/Dynamic-loading runtimes.
* **`libssl.so` & `libcrypto.so`**: Cryptographic and TLS/SSL primitives required by `ssl` module, `urllib`, `requests`, and `aiohttp`.
* **`libz.so`**: Compression support for `zipfile`, `zlib`, and `.whl` package extraction.
* **`libsqlite3.so`**: Embedded database storage used extensively by OSINT tools like Maigret.

---

## 4. Diagnostic & Inspection Commands

* **`python-doctor`**: Audits CPython engine availability, target ABI, standard library presence, user bin status, and PATH integration.
* **`python-env`**: Dumps complete Python environment configuration, site-packages paths, and supported OSINT target tool status.
* **`python` / `python3`**: Direct interactive or batch execution, or honest prototype status report if the binary is pending acquisition.

---

## 5. Roadmap to Sherlock & Maigret

1. **v0.74 (Current)**: Python Environment Architecture, `$HOME/.local/bin` in PATH, `PythonEnvironmentService`, and `python-doctor`.
2. **v0.75 (Next)**: CPython 3.11 ARM64 Binary Acquisition & Packaging (`libtermode_python_exec.so`).
3. **v0.76**: Standard Library Packaging (`usr/lib/python3.11`) and Interactive REPL verification.
4. **v0.77**: Upstream `pip` integration (`ensurepip` / `pip install --user`).
5. **v0.78**: Verification with pure-Python packages (`requests`, `colorama`).
6. **v0.79**: Physical hardware verification running **Sherlock** (`sherlock <username>`) and **Maigret** on Samsung Galaxy Tab S9 FE.
