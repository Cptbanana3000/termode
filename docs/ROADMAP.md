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

These are **planned, not installed**. v0.45 proves the Git installer path on top
of the v0.44 runtime package installer prototype but ships no Git artifact, so
Git is reported planned/not installed and the installer refuses safely. See
[Git Support Strategy](GIT_SUPPORT_STRATEGY.md),
[Binary Package Installer Prototype](BINARY_PACKAGE_INSTALLER_PROTOTYPE.md),
[Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md) and
[Runtime Expansion Architecture](RUNTIME_EXPANSION_ARCHITECTURE.md).

## Runtime Expansion Roadmap

- v0.41 Beta Feedback Fixes / RC Cleanup
- v0.42 Runtime Expansion Architecture
- v0.43 Prefix / PATH / Environment System
- v0.44 Binary Package Installer Prototype
- v0.45 Git Support Feasibility / Installer Path (current)
- v0.46 Git Package Artifact / Real Git Execution
- v0.47 Node.js Support
- v0.48 npm Support
- v0.49 Python Support
- v0.50 Dev Stack Presets
- v0.51 Full Terminal QA
- v0.52 Complete Termode Beta
- CalypsoIDE integration later

## Product First

The standalone terminal experience comes first: reliable REAL PTY, packages,
workspaces, sessions, terminal UX, honest doctors, and a guided runtime layer.
CalypsoIDE integration stays out of scope until the standalone beta is complete.
