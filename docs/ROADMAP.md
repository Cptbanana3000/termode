# Roadmap

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
- runtime package installer prototype with `hello-bin`

## What Termode Does Not Have Yet

- Node.js
- npm
- Git
- Python
- a full Linux package ecosystem
- compilers
- full Termux-replacement status

These are **planned, not installed**. v0.53 defines audited Git source and
dependency preparation (version selected, Perl requirement documented, dependency strategy
defined), but still ships no real Git artifact, so Git is reported
planned/not installed and the installer refuses safely. See
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
- v0.62 Git Bash Build Fixes (current)
- v0.63 Git Artifact Packaging / Install QA
- v0.64+ Node.js / npm / Python / Dev Stack Presets
- v0.63 Full Terminal QA · v0.64 Complete Termode Beta
- CalypsoIDE integration later

v0.62 resolves compile blockers (missing headers/libraries like OpenSSL, thread cancellation under Bionic, sync_file_range) and successfully compiles a real Git 2.44.0 arm64-v8a binary under Git Bash using a minimal-local build strategy. See [Git Bash Build Fixes Status](GIT_BASH_BUILD_FIXES_STATUS.md) and [Git Bash Build Logs](GIT_BASH_BUILD_LOGS.md).

## Product First

The standalone terminal experience comes first: reliable REAL PTY, packages,
workspaces, sessions, terminal UX, honest doctors, and a guided runtime layer.
CalypsoIDE integration stays out of scope until the standalone beta is complete.
