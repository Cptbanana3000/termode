# Termode QA Checklist

Use this checklist for v0.36 beta readiness testing on Android.

For the v0.37 device bug bash, start with:

- `qa-run`
- `qa-status`
- `qa-report`
- `bug-report`

v0.37.1 notes:

- debug APK install on the connected Android device succeeded
- command execution worked after unlocking the device
- `qa-status`, `doctor`, beta/settings/package/workspace/session/preview,
  localhost, native-tool, and js-proof doctors ran without crashing
- `host-rm` now removes empty directories while still blocking protected roots
- host file commands now reject explicit `..` parent traversal
- `qa-status` now reports limited readiness separately from needs-fixes
- unified doctor now prefers explicit `Overall:` / `Status:` lines
- package helper reload prompt refresh no longer merges into package output

v0.38 onboarding checks:

- run `welcome`
- run `examples`
- run `examples packages`
- run `examples workspace`
- run `glossary`
- run `onboarding-doctor`
- confirm README/docs match the in-app guidance

v0.39 UI / settings checks:

- run `settings-summary` and confirm all settings are listed
- run `settings-doctor` and confirm `Overall: HEALTHY`
- run `terminal-settings` and `keyboard-settings`
- run `theme-test` and confirm normal/dim/bold/ANSI/badges are readable
- run `status` in NORMAL and after `default-shell`
- run `settings-reset-safe` (should require `--confirm`)
- run `settings-reset-safe --confirm` and confirm packages/workspaces/sessions
  survive
- open Settings screen and confirm version reads `v0.39`, and line height,
  scrollback, ANSI debug, keep-screen-on, and Safe Reset controls are present

## App Launch

- launch app
- verify welcome/onboarding commands are readable
- run `commands`
- run `doctor`
- run `beta-status`

## Shell

- run `default-shell`
- type `pwd`
- run `mode`
- stop and restart shell
- verify prompt and keyboard controls

## Packages

- run `pkg doctor`
- run `pkg list`
- install and remove a script package
- verify helper reload stays silent
- run `reload-helpers`

## Workspace

- run `workspace-init beta`
- run `workspace-cd beta`
- run `host-write hello.txt "hello beta"`
- run `host-cat hello.txt`
- run `workspace-doctor`

## Storage

- run `storage-status`
- link storage if available
- test import/export if available

## Terminal UX

- run `keyboard-test`
- run `ansi-test`
- run `scroll-test 300`
- test copy/paste
- test a large paste warning
- rotate screen

## Preview

- run `preview`
- run `preview-url 3000`
- run `preview-doctor`
- run `localhost-doctor`

## Persistence

- create multiple tabs
- close a tab
- force close/reopen app
- verify session/history/scrollback restore as expected

## Bug Report

- run `bug-report`
- confirm it excludes private environment variables, tokens, and full sensitive
  paths

## Release Blockers

- app crash during common QA commands
- duplicate REAL PTY shell starts or prompts
- workspace path escape or protected path deletion
- package helper reload leak/regression
- doctor reporting healthy while a critical subsystem is broken

## v0.38 Device Note

- debug APK install was verified on a real Android device
- automated `adb input text` dropped characters in the active terminal, so the
  command checklist still needs a human typed pass
- stale startup banner text was fixed to `Termode v0.38`

## v0.39 Device Note

- startup banner and `version` now report `Termode v0.39`
- Settings screen app version was corrected from the stale `0.4.0` string
- automated `adb input text` remains unreliable against the live terminal, so
  the typed-command UI pass is still a manual hand check

## v0.40 Beta Candidate checks

- run `version` and `build-info` and confirm `v0.40`
- run `beta-candidate` (overview), `beta-candidate status`, `beta-candidate
  checklist`, `beta-candidate notes`, `beta-candidate limits`
- run `beta-candidate ready` and confirm `Ready for beta testing.`
- confirm `doctor`, `beta-status`, and `qa-status` still report healthy or an
  accepted limited state (frozen runtime / unlinked storage are acceptable)
- install the renamed beta artifact `Termode-v0.40-beta-debug.apk` and run the
  first checks from `BETA_INSTALL.md`

## v0.40 Device Note

- startup banner and `version`/`build-info` report `Termode v0.40`
- Android `versionName` is `0.40.0`, `versionCode` is `40`
- `adb shell input text` works for the typed pass while the soft keyboard is
  raised (tap the terminal body first); it drops characters when the keyboard
  is dismissed

## v0.41 RC cleanup checks

- run `version` and `build-info` and confirm `v0.41`
- run `feedback`, `feedback template`, `feedback checklist`
- run `rc-checklist` and `rc-status` (confirm `RC CLEANUP READY`)
- run `beta-candidate ready` (confirm `Ready for beta testing.`)
- confirm `doctor` may be `LIMITED` only for intentional reasons (frozen runtime
  / unlinked storage) and `qa-status` is `READY WITH LIMITATIONS`
- confirm `settings-reset-safe` still requires `--confirm` and keeps user data
- install the renamed RC artifact `Termode-v0.41-rc-debug.apk`

## v0.41 Device Note

- startup banner and `version`/`build-info` report `Termode v0.41`
- Android `versionName` is `0.41.0`, `versionCode` is `41`
- when driving the device with `adb`, confirm Termode is the foreground app
  first (`dumpsys activity activities | grep topResumedActivity`) and keep the
  soft keyboard raised; only the first typed command after a tap lands, so
  re-tap before each command
