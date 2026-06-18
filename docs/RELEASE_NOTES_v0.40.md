# Termode v0.40 — Beta Candidate

Termode is a standalone Android terminal app built around a **real native PTY**
shell (`/system/bin/sh` over a true pseudo-terminal). It focuses on a
shell-first mobile workflow with script packages, workspaces, and honest
diagnostics. This is a **beta candidate**: feature-stable for testing, but bugs
are expected. It is not a stable v1.0 and is not a Termux replacement.

## What Is Working

- REAL PTY shell sessions with host command interception
- shell-first command entry
- script packages via `pkg`
- trusted remote script package repo flow (trust / upgrade / repair / verify)
- workspaces under Termode app storage
- safe host file commands (`host-write`, `host-cat`, `host-ls`, etc.)
- Android storage bridge when a folder is linked (SAF)
- sessions, tabs, history, and scrollback persistence
- terminal UX: keyboard, ANSI, paste, copy, scrollback helpers
- settings / theme / status readouts and a data-safe visual reset
- preview / localhost diagnostics
- built-in JNI native tools and the `js-proof` controlled evaluator
- QA / beta / onboarding tooling and doctors

## Main Features

- **REAL PTY shell** — a true pseudo-terminal attached to the Android shell.
- **Shell-first UX** — type commands directly; Termode intercepts management
  commands (`pkg`, `workspace-*`, `doctor`, etc.).
- **Packages** — script packages installed into the sandbox and exposed as
  shell helpers.
- **Remote repo** — trusted remote script package index with trust, upgrade,
  and repair flows.
- **Workspaces** — project folders with safe `host-*` file commands.
- **Host file commands** — read/write inside Termode home with path-traversal
  protection.
- **Terminal UX** — ANSI rendering, paste safety, copy helpers, scrollback,
  and an accessory key row.
- **Preview / localhost** — port checks, HTTP tests, and preview URLs for
  future dev-server workflows.
- **Runtime freeze** — the runtime direction is intentionally frozen; see
  `runtime-freeze`.
- **QA / beta tooling** — `doctor`, `qa-status`, `beta-status`, `beta-score`,
  `bug-report`, and the new `beta-candidate` commands.

## Known Limitations

- Node.js / npm are not included.
- Python / Git are not included.
- Native binary packages are not supported.
- QuickJS / Duktape are deferred (probe surfaces only).
- Direct app-bin execution may be blocked by Android.
- Storage features need an Android folder to be linked.
- Beta software; bugs are expected.

## Install / Testing

1. Build or obtain the debug APK: `Termode-v0.40-beta-debug.apk`.
2. Enable "Install unknown apps" for the installer source.
3. Install and launch Termode.

See [BETA_INSTALL.md](BETA_INSTALL.md) for detailed steps and how to clear app
data, and [BETA_TESTING.md](BETA_TESTING.md) for the tester checklist.

## Suggested First Commands

```sh
welcome
build-info
status
doctor
beta-candidate status
beta-candidate ready
qa-status
```

Then try the core flow:

```sh
default-shell
pwd
pkg install hello
hello
workspace-init beta40
workspace-cd beta40
host-write hello.txt "hello beta"
host-cat hello.txt
```

## Reporting Bugs

Run `bug-report` and copy the output. It includes the version, ABI, and doctor
summaries, and deliberately omits private environment variables, tokens, and
full file paths.

## Not Supported Yet

- Node.js / npm / Python / Git
- native binary packages
- a full Linux distribution environment
