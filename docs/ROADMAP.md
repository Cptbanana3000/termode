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

## What Termode Does Not Have Yet

- Node.js
- npm
- Git
- Python
- a full Linux package ecosystem
- compilers
- full Termux-replacement status

These are **planned, not installed**. v0.42 builds the architecture for them;
real installs come in later milestones. See
[Runtime Expansion Architecture](RUNTIME_EXPANSION_ARCHITECTURE.md).

## Runtime Expansion Roadmap

- v0.41 Beta Feedback Fixes / RC Cleanup
- v0.42 Runtime Expansion Architecture (current)
- v0.43 Prefix / PATH / Environment System
- v0.44 Binary Package Installer Prototype
- v0.45 Git Support
- v0.46 Node.js Support
- v0.47 npm Support
- v0.48 Python Support
- v0.49 Dev Stack Presets
- v0.50 Full Terminal QA
- v0.51 Complete Termode Beta
- CalypsoIDE integration later

## Product First

The standalone terminal experience comes first: reliable REAL PTY, packages,
workspaces, sessions, terminal UX, honest doctors, and a guided runtime layer.
CalypsoIDE integration stays out of scope until the standalone beta is complete.
