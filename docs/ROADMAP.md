# Roadmap

Current milestone: **v0.71 Dev Server Supervision & Background Process Management**. Providing
native background daemon registry, process lifecycle management (PID, uptime, CWD, memory),
port detection, buffered stdout/stderr logging, graceful termination and socket release,
interactive shell commands (`dev-server list`, `stop`, `logs`, `open`, `doctor`),
and terminal UI status indicators verified against Chrome on physical hardware.
The next milestone is **v0.72 npm Package Installation & Module Resolution**.

Termode is building a complete standalone Android terminal/dev environment
first — easier and more guided than Termux — and only later integrating into
CalypsoIDE as a plug-and-play terminal/runtime engine.

## What Termode Has Today

- terminal foundation
- REAL PTY shell
- script packages (with remote repo / trust / upgrade / repair)
- workspaces and host file commands
- tabs, sessions, history, scrollback, restore
- QA / beta / onboarding tooling and doctors
- safe prefix/PATH/environment infrastructure
- runtime package installer with `hello-bin` and reviewed local-only Git
- real local Git 2.44.0 on supported arm64-v8a Android devices
- **authentic upstream Google V8 Node.js v24.18.0 runtime engine** with full Bionic dynamic libraries on ARM64
- developer stack presets (node-express, static-web, react-ts) and Calypso IDE bridge facade

## What Termode Does Not Have Yet

- npm registry client / live remote package downloads (in progress)
- remote Git transports and advanced Git helpers
- Python
- a full Linux package ecosystem
- compilers
- full Termux-replacement status

These remain **planned, not installed**. The local-only Git subset is supported
after v0.64 on-device smoke verification; remote Git remains planned. See
[Git Support Strategy](GIT_SUPPORT_STRATEGY.md),
[Git Artifact Production Status](GIT_ARTIFACT_PRODUCTION_STATUS.md),
[Git Trusted Build](GIT_TRUSTED_BUILD.md),
[Git Artifact Build Status](GIT_ARTIFACT_BUILD_STATUS.md),
[Git arm64-v8a Artifact Pipeline](GIT_ARM64_ARTIFACT_PIPELINE.md),
[Git Artifact Acquisition](GIT_ARTIFACT_ACQUISITION.md),
[Git Build Pipeline](GIT_BUILD_PIPELINE.md),
[Git Bundle Smoke Test](GIT_BUNDLE_SMOKE_TEST.md),
[Binary Package Installer Prototype](BINARY_PACKAGE_INSTALLER_PROTOTYPE.md),
[Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md) and
[Runtime Expansion Architecture](RUNTIME_EXPANSION_ARCHITECTURE.md).

## Runtime Expansion Roadmap

- v0.41 Beta Feedback Fixes / RC Cleanup
- v0.42 Runtime Expansion Architecture
- v0.43 Prefix / PATH / Environment System
- v0.44 Binary Package Installer Prototype
- v0.45 Git Support Feasibility / Installer Path
- v0.46 Real Git Package Artifact / Execution Probe
- v0.47 Git Artifact Acquisition / Build Pipeline
- v0.48 Verified Git Artifact Bundle / Smoke Test
- v0.49 Git Artifact Build / arm64-v8a Production
- v0.50 Git Artifact Production / Trusted Build
- v0.51 Git Artifact Build Environment / NDK Source Build
- v0.52 Git Source Acquisition / Dependency Build Plan
- v0.53 Git Source + Dependency Preparation
- v0.54 Git Build Prerequisite Resolution
- v0.55 Git Prerequisite Acquisition / Source Staging
- v0.56 Git Perl Resolution / arm64 Build Readiness
- v0.57 Git Perl Setup / Build Readiness Finalization
- v0.58 Git arm64 Build Attempt
- v0.59 Git Build Fixes
- v0.60 Git Build Host Strategy
- v0.61 Git arm64 Build Under Git Bash
- v0.62 Git Bash Build Fixes
- v0.63 Git Artifact Packaging / Install QA
- v0.64 Git On-Device Execution Fixes
- v0.65 Local Git UX Polish
- v0.66 Node.js arm64 Prototype
- v0.67 npm Package Management Prototype
- v0.69 Node.js & Full Runtime Bundling QA
- v0.70 Authentic Google V8 Node.js Runtime Engine & Full Packaging
- v0.71 Dev Server Supervision & Background Process Management (current)
- v0.72 npm Package Installation & Module Resolution (next)
- later: Python / Native Package Ecosystem
- Calypso IDE embedding via TermodeEngine & TermodeEmbeddableTerminal

v0.62 resolves compile blockers (missing headers/libraries like OpenSSL, thread cancellation under Bionic, sync_file_range) and successfully compiles a real Git 2.44.0 arm64-v8a binary under Git Bash using a minimal-local build strategy. See [Git Bash Build Fixes Status](GIT_BASH_BUILD_FIXES_STATUS.md) and [Git Bash Build Logs](GIT_BASH_BUILD_LOGS.md).

## Product First

The standalone terminal experience comes first: reliable REAL PTY, packages,
workspaces, sessions, terminal UX, honest doctors, and a guided runtime layer.
CalypsoIDE integration stays out of scope until the standalone beta is complete.
