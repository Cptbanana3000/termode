# Termode v0.37 Device QA Bug Bash

v0.37 is a real-device QA pass. It does not add runtimes or large new systems.
The goal is to make Termode beta-testable by finding rough edges, confirming
doctor accuracy, and keeping failures short and actionable.

## Commands

- `qa-run`
- `qa-status`
- `qa-report`
- `qa-reset`
- `bug-report`
- `doctor`
- `beta-status`

## Manual Android Checklist

Startup:

- fresh install or clear app data if safe
- open Termode
- run `welcome`
- run `doctor`
- run `beta-status`
- force close and reopen
- confirm no duplicate prompts or shells

Shell:

- `default-shell`
- `pwd`
- `echo hello`
- Ctrl+C
- `stop-shell`
- `stop-shell`
- `default-shell`
- `default-shell`
- `session-info`
- `session-doctor`

Tabs:

- `tabs`
- `tab-new`
- `tab-rename qa`
- `tab-switch 1`
- `tab-close`
- `tabs`

Packages:

- `pkg doctor`
- `pkg list`
- `pkg install hello`
- `hello`
- `pkg verify hello`
- `pkg remove hello`
- `pkg repair`
- `pkg repo status`
- `pkg repo test`

Workspace/files:

- `workspace-init qa`
- `workspace-cd qa`
- `pwd`
- `pwd-host`
- `host-write hello.txt "hello qa"`
- `host-cat hello.txt`
- `host-ls`
- `host-rm hello.txt`
- `workspace-doctor`

Terminal UX:

- `keyboard-test`
- `ansi-test`
- `scroll-test 300`
- `copy-last`
- `copy-session 20`
- paste large text if possible
- `paste-force` if blocked
- `resize-info`

Preview:

- `preview-url 3000`
- `preview-copy 3000`
- `preview-open 3000`
- `preview-open 3000 --force`
- `preview-check 3000`
- `preview-doctor`
- `localhost-doctor`

Runtime frozen:

- `runtime-freeze status`
- `runtime-freeze doctor`
- `js-proof doctor`
- `quickjs doctor`
- `duktape doctor`
- `native-tool doctor`
- `runtime-doctor`

QA:

- `qa-run`
- `qa-status`
- `qa-report`
- `bug-report`
- `qa-checklist`

## Expected Results

- no crashes
- no duplicate shell starts
- no duplicate prompts
- helper reload remains silent
- package/workspace/session/preview features still work
- doctors are healthy or limited for known reasons
- deferred runtime probes do not mark the app broken
- errors are short and actionable

## v0.37.1 Manual QA Result

On-device QA was run through Android SDK platform-tools against the debug APK.
The first launch was blocked by the device lockscreen bouncer; after the device
was unlocked, Termode launched in REAL PTY mode and command input worked.

Observed:

- `adb install -r build/app/outputs/flutter-apk/app-debug.apk` succeeded
- `com.termode.termode/.MainActivity` launched
- REAL PTY badge was visible and accurate
- `qa-status` ran without crashing
- `doctor` ran without crashing
- beta, settings, package, workspace, session, preview, localhost,
  native-tool, and js-proof doctors ran without crashing
- no duplicate prompts were observed in the tested command path

Fixed during the v0.37.1 pass:

- `qa-status` now distinguishes ready, limited, and needs-fixes states
- `host-rm` can remove empty directories created by `host-mkdir`
- `host-rm` keeps protected Termode roots blocked
- host file commands now reject explicit `..` parent traversal
- unified doctor now prefers explicit `Overall:` / `Status:` lines over
  incidental LIMITED text in doctor bodies
- `runtime-freeze doctor` accepts the embedded freeze decision when repo docs
  are not present inside the installed APK
- host-intercepted package output no longer merges with the post-reload shell
  prompt, fixing lines like `Try: hellotermode:$`

Remaining manual work:

- confirm REAL PTY focus, keyboard, copy/paste, and scroll behavior by hand
- confirm package helper reload remains silent on device
- capture any bad wrapping/readability issue visible only on the handset

## v0.38 Onboarding QA Additions

Run:

```sh
welcome
getting-started
first-run
help
commands
commands --all
examples
examples packages
examples workspace
examples preview
examples runtime
glossary
beta-known-limits
onboarding-doctor
version
release-notes
beta-next
runtime-freeze next
```

Expected:

- first-run text is compact
- examples are copy-friendly
- limitations are clear
- runtime remains frozen
- onboarding-doctor is healthy

Manual device result for v0.38:

- debug APK installed successfully on a real Android device
- `adb input text` was unreliable with the active terminal/key handling and
  dropped characters, so the full typed checklist still needs a hand pass
- a stale startup banner was found during device inspection and fixed from
  `Termode v0.9.2` to `Termode v0.38`
- startup hints now point to `welcome`, `commands`, and `beta-known-limits`
- automated tests cover the new onboarding commands and REAL PTY interception

## Acceptable LIMITED Statuses

- storage is LIMITED when no Android folder is linked
- runtime is LIMITED when direct app-bin execution is blocked
- QuickJS and Duktape are deferred/unavailable probes
- preview may be LIMITED if no app can open a URL

## Release Blocking

- app crash during common commands
- duplicate shell starts or zombie PTY after tab close
- package install/remove breaks helper reload
- workspace path escapes app/project roots
- doctor reports HEALTHY while a critical subsystem is broken
- bug-report exposes secrets, environment dumps, or private tokens

## Non-Blocking Limitations

- Node.js/npm/Python/Git are not included
- native binary packages are not supported
- closed preview ports show friendly errors
- Android storage features depend on user-granted folder access
- manual QA may be blocked if the device is locked or unavailable

## Bug Reports

Run:

```sh
bug-report
qa-report
```

Copy the output into the issue. Do not include screenshots or logs containing
tokens, private repository URLs, or secrets.
