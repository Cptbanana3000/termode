# GEMINI.md - Agent Operating Rules for Termode

This document defines the strict, binding operational rules for AI assistants (Gemini / Antigravity) working on the Termode project. These rules take precedence over all default agent assumptions and must be strictly enforced at all times.

---

## 1. Absolute Authenticity & Prohibition of Mock/Fake Results (Strictly Enforced)

- **NO FAKE OR MOCKED RUNTIMES**: Never implement, simulate, or claim a native engine (e.g., Node.js, Python, Git, C/C++) works by printing hardcoded terminal text or mock responses.
- **REAL MEANS REAL**:
  - If a runtime or tool is claimed to be installed and working, it must be an authentic, full executable running on the target architecture (`arm64-v8a`).
  - If a server is reported as listening on a port (e.g., `localhost:3000`), it MUST actually bind a real OS socket, listen on the network interface, and serve authentic HTTP responses verified via browser or socket connection.
- **HONEST LIMITATIONS & TRANSPARENCY**:
  - If a binary, tool, or library cannot yet execute fully, has missing dependencies, or requires additional patches, report the exact failure state, missing shared libraries, or technical roadblocks immediately.
  - Never disguise a lightweight CLI stub or shim as the full upstream runtime. Clearly distinguish between "scaffold/stub" and "authentic engine (V8, CPython, etc.)".

---

## 2. Hardware Verification & Screenshot Testing

- **PHYSICAL DEVICE FIRST**:
  - Whenever a physical device or emulator is connected via ADB (e.g. Samsung Galaxy Tab S9 FE - `R52Y80FHQKR`), build and install the real APK (`adb install -r <apk>`).
  - Verify every feature directly on the physical hardware by injecting commands and keystrokes.
- **VISUAL & SOCKET CONFIRMATION**:
  - Capture real device screenshots (`adb shell screencap -p`) and visually inspect them before claiming a feature works.
  - For servers and network listeners, verify via `netstat -tlpn` / `ss -tlpn` and test live HTTP connectivity through Chrome or curl.

---

## 3. Android Security & Native Execution Compliance

- **W^X COMPLIANCE (Android 10+)**:
  - Never attempt to execute binaries directly out of writable app storage (`/data/data/.../files/`) as Android's kernel SELinux rules enforce Write XOR Execute (`noexec`).
  - Executable native payloads must be packaged as native shared libraries (`lib*.so`) in `jniLibs/<abi>/` to reside in `applicationInfo.nativeLibraryDir`, or linked via legitimate Android execution mechanisms.
- **ISOLATED RUNTIME ENVIRONMENT**:
  - Do not rely on external app directories (such as hardcoded `/data/data/com.termux/` paths).
  - Explicitly sanitize environment variables (e.g., `OPENSSL_CONF=/dev/null`, `LD_LIBRARY_PATH`, `PATH`) so that native binaries run independently within Termode's own sandbox.

---

## 4. Codebase Boundary & Repository Isolation

- **STRICT PROJECT SCOPE**:
  - All modifications must stay strictly within `D:\Projects\termode`.
  - **NEVER** edit, modify, delete, or touch files in external repositories (e.g., `D:\Projects\calypso_ide`) unless explicitly instructed with clear user confirmation.
- **PRESERVE EXISTING FUNCTIONALITY**:
  - Keep documentation integrity and existing comments intact.
  - Ensure 100% passing automated test suite with 0 regressions before concluding milestones.

---

## 5. UI Design & Anti-Slop Discipline

- **90/10 RULE**: 90% neutral foundation (Zinc, Slate, or deep charcoal; pure dark backgrounds), 10% single muted spot accent color (e.g., terminal emerald `#00FF66` or restrained cyan).
- **NO AI CLICHÉS**:
  - Strictly ban `bg-gradient-to-*` multi-stop gradients, neon violet/fuchsia blobs, and glowing floating shadows.
  - Keep terminal UI clean, responsive, high-contrast, and focused on developer productivity.
