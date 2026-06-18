# Termode v0.36 Beta Readiness

v0.36 is a product stabilization pass. It does not add new runtimes. It makes
Termode easier to understand, diagnose, and test as a standalone Android
terminal.

## Supported Today

- REAL PTY shell-first terminal
- script packages through `/system/bin/sh`
- trusted remote script package repository flow
- workspace folders under Termode app storage
- Android storage bridge where linked by the user
- sessions, tabs, history, and scrollback persistence
- terminal UX helpers for keyboard, paste, ANSI, copy, and scrollback
- localhost/preview diagnostics
- built-in JNI native tools
- `js-proof` controlled evaluator
- frozen runtime decision via `runtime-freeze`

## Known Limits

- No Node.js, npm, Python, or Git.
- Native binary packages are not supported.
- QuickJS and Duktape are probe surfaces only.
- Direct app-bin execution may be blocked by Android.
- Storage import/export may be limited by Android storage permissions.
- Some terminal apps/features may not behave exactly like desktop Linux.
- This is beta software.

## Deferred

- QuickJS integration
- Duktape integration
- Node.js
- npm
- Python
- Git
- native binary package installs
- native package manager

## Readiness Criteria

Termode is beta-ready when these checks are consistently healthy or clearly
limited on device:

- `doctor`
- `beta-status`
- `pkg doctor`
- `workspace-doctor`
- `session-doctor`
- `runtime-freeze doctor`
- `preview-doctor`
- `localhost-doctor`
- `native-tool doctor`
- `js-proof doctor`

Use `beta-checklist` and `qa-checklist` for the manual pass.

v0.37 adds `qa-run`, `qa-status`, `qa-report`, and `qa-reset` for the device
bug-bash pass. See [DEVICE_QA_BUG_BASH.md](DEVICE_QA_BUG_BASH.md).

v0.37.1 keeps the runtime decision frozen and focuses on QA rough edges:

- `qa-status` reports `READY WITH LIMITATIONS` when only accepted LIMITED
  statuses are present
- `host-rm` can remove empty workspace directories created by `host-mkdir`
- protected Termode roots remain blocked from host file deletion
- host file commands reject explicit `..` parent traversal
- unified doctor recognizes package `Status: HEALTHY`
- `runtime-freeze doctor` works inside the installed APK using the embedded
  freeze decision when repo markdown files are unavailable

v0.38 focuses on documentation and onboarding:

- `welcome`, `getting-started`, and `first-run` are compact first-run guides
- `examples` provides copy-friendly command examples by category
- `glossary` explains beginner terms
- `onboarding-doctor` checks onboarding/docs readiness
- README and docs now point new beta testers to the same starting flow
- the startup banner now reports `Termode v0.38` and points to onboarding
  commands

Known v0.38 QA limitation:

- automated `adb input text` was unreliable on the test device, so full manual
  command entry remains a hand checklist item

v0.39 focuses on UI and settings polish (no new runtimes):

- `settings-summary` now lists theme, font size, line height, cursor, blink,
  scrollback, paste limits, keep-screen-on, and welcome banner
- `settings-doctor` adds font-size and line-height health checks
- `settings-reset-safe --confirm` restores visual/terminal defaults without
  touching packages, workspaces, sessions, history, repo config, or files
- `theme-test` prints a readability sample (normal/dim/bold/ANSI/badges)
- `status` prints a compact mode/shell/session/workspace/packages/runtime/beta
  summary
- the settings screen exposes line height, scrollback, ANSI debug, keep screen
  on, a safe visual reset, and the correct app version
- the startup banner now reports `Termode v0.39`
- tab name/badge wrapping and prompt/keyboard spacing were tightened

The runtime decision remains frozen. Node.js, npm, Python, Git, QuickJS, and
Duktape are still not added.

v0.40 packages Termode as a beta candidate (no new features):

- `build-info` reports app/version/build-type/runtime/shell/packages and the
  expected beta artifact name
- `beta-candidate` adds `status`, `checklist`, `notes`, `limits`, and `ready`
- the startup banner and `version` report `Termode v0.40`; Android
  `versionName` is `0.40.0` and `versionCode` is `40`
- release/install/testing docs were added (`RELEASE_NOTES_v0.40.md`,
  `BETA_INSTALL.md`, `BETA_TESTING.md`)

Beta readiness treats intentional limitations as acceptable: a frozen runtime,
deferred QuickJS/Duktape, and unlinked storage are reported as `FROZEN` /
`LIMITED` and do NOT make Termode "not ready". Only a genuinely `UNHEALTHY`
core subsystem (packages, workspaces, sessions) blocks `beta-candidate ready`.

v0.41 is a beta-feedback / release-candidate cleanup pass (no new features):

- version is `v0.41` (Android `versionName 0.41.0` / `versionCode 41`)
- `feedback`, `feedback template`, `feedback checklist` help testers file useful
  bug reports locally (no network)
- `rc-checklist` lists the final pre-release checklist; `rc-status` reports a
  compact release-candidate status (`RC CLEANUP READY` when core systems are OK)
- `rc-status` uses the same readiness logic as `beta-candidate ready`, so the
  intentional frozen runtime and unlinked storage do NOT block RC readiness
- stale wording was cleaned up (e.g. `runtime-freeze next` now points to the
  current next milestone)

A `LIMITED` doctor status is expected when the only issues are intentional
(frozen runtime, unlinked storage); it does not mean Termode is broken.

v0.42 begins the runtime expansion architecture (planning only, no real
installs):

- version is `v0.42` (Android `versionName 0.42.0` / `versionCode 42`)
- a controlled Termode prefix under `TERMODE_HOME` with `prefix-info`,
  `prefix-init`, `prefix-doctor`, `path-info`, `env-info`
- toolchain planning: `toolchain-status`, `toolchain-list`, `toolchain-info`,
  `toolchain-plan`, `toolchain-doctor`
- install planning: `runtime-install list|plan|status|doctor`
- guided presets planning: `dev-setup list|plan`, `dev-doctor`
- runtime-freeze wording now clarifies that implementation is frozen for the
  beta foundation while expansion architecture is active; real Node/Git/Python
  are still not installed

Beta readiness is unaffected by planned-but-missing toolchains: `beta-candidate
ready` only blocks on a genuinely `UNHEALTHY` core subsystem (packages,
workspaces, sessions). Toolchain/runtime-install/dev doctors report
`ARCHITECTURE PHASE` / `LIMITED`, never `UNHEALTHY`, for missing planned tools.

v0.43 turns the prefix/PATH/environment layer into usable infrastructure:

- version is `v0.43` (Android `versionName 0.43.0` / `versionCode 43`)
- `TERMODE_PREFIX` is unified with the existing `files/usr` package prefix so
  script packages and helper reload keep working
- REAL PTY shells receive Termode environment variables and a safe PATH overlay
- new checks: `prefix-status`, `path-status`, `path-preview`, `path-doctor`,
  `env-status`, `env-preview`, `env-doctor`, `env-check`, `env-script`
- bin/shim planning: `bin-list`, `bin-which`, `bin-doctor`, `shim-info`,
  `shim-list`, `shim-doctor`
- `runtime-install status` and `dev-doctor` now distinguish planning-only from
  environment-ready state

Git, Node.js, npm, and Python remain planned but not installed.
