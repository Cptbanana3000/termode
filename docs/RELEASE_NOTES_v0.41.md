# Termode v0.41 — Beta Feedback Fixes / Release Candidate Cleanup

v0.41 is a cleanup pass on top of the [v0.40 beta candidate](RELEASE_NOTES_v0.40.md).
It focuses on real-world beta-testing readiness: small wording/readability fixes,
beta feedback helpers, a release-candidate checklist, and regression hardening.
**No major features were added and the runtime decision stays frozen.**

Termode is still beta software. It is not a stable v1.0 and not a Termux
replacement.

## Purpose

- make it easy for beta testers to report useful bugs (`feedback`)
- give a clear release-candidate checklist and status (`rc-checklist`, `rc-status`)
- remove stale version/wording and harden regressions

## What Changed Since v0.40

- version bumped to **v0.41** (banner, `version`, `build-info`, release notes,
  `bug-report`, `qa-report`, beta-candidate output, settings screen); Android
  `versionName 0.41.0` / `versionCode 41`
- new `feedback`, `feedback template`, `feedback checklist` commands (local only,
  no network)
- new `rc-checklist` and `rc-status` commands for release-candidate readiness
- `runtime-freeze next` now points to the current next milestone (was stale)
- docs refreshed for the RC cleanup pass
- regression checks: no stale version text, no duplicate prompt after restore,
  no helper-reload marker leak, no badge wrapping, `settings-reset-safe` stays
  data-safe, `beta-candidate ready` / `rc-status` stay correct under intentional
  limitations

## Current Status

- REAL PTY shell, packages, workspaces, sessions, terminal UX, preview/localhost,
  QA/beta tooling all working
- `beta-candidate ready` → "Ready for beta testing."
- `rc-status` → "RC CLEANUP READY" when core systems are healthy
- `doctor` may report `LIMITED` purely because of the intentional frozen runtime
  and/or unlinked storage — that is expected, not a failure

## How to Install the Beta APK

1. Build or obtain `Termode-v0.41-rc-debug.apk`.
2. Enable "Install unknown apps" for the installer source.
3. Install and launch Termode.

See [BETA_INSTALL.md](BETA_INSTALL.md) for full steps.

## First Commands to Run

```sh
welcome
build-info
rc-status
beta-candidate ready
doctor
qa-status
feedback
```

## What to Test

```sh
default-shell
pwd
pkg doctor
pkg install hello
hello
pkg remove hello
workspace-init rc41
workspace-cd rc41
host-write hello.txt "hello rc41"
host-cat hello.txt
settings-reset-safe --confirm
theme-test
session-doctor
```

Then force-close and reopen, confirm there is no crash and a single prompt, and
run `rc-status` and `beta-candidate ready` again.

## Known Limitations

- Node.js / npm are not included.
- Python / Git are not included.
- Native binary packages are not supported.
- QuickJS / Duktape are deferred.
- Direct app-bin execution may be blocked by Android.
- Storage features need an Android folder to be linked (shows `LIMITED` until then).
- A `LIMITED` doctor is not always broken — it is often an intentional limitation.
- Beta software; bugs are expected.

## Not Supported Yet

- Node.js / npm / Python / Git
- native binary packages
- a full Linux distribution environment

## How to Report Bugs

Run `feedback` for the reporting steps and `feedback template` for a copy-friendly
form. Include the output of `bug-report` and `qa-report` (both omit private
environment variables, tokens, and full file paths). See [BETA_TESTING.md](BETA_TESTING.md).
