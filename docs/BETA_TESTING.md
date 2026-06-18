# Beta Testing

Thanks for testing the Termode beta candidate. This is beta software — bugs are
expected. This page explains what to check, what to report, and which behaviors
are intentional.

## Short Tester Checklist

```sh
welcome
build-info
doctor
beta-candidate status
beta-candidate ready
qa-status
default-shell
pwd
echo hello
pkg doctor
pkg install hello
hello
pkg remove hello
workspace-init beta40
workspace-cd beta40
host-write hello.txt "hello beta"
host-cat hello.txt
session-doctor
```

Then force-close and reopen the app and confirm there is no crash and no
duplicate prompt, and run `doctor` and `beta-candidate ready` again.

## What to Report

- the command you ran and what you expected
- what actually happened (copy the output)
- whether it is reproducible
- your device model and Android version
- the `build-info` and `bug-report` output

## How to Run bug-report

```sh
bug-report
```

Copy the full output into your report. It includes the Termode version, Android
ABI, and doctor summaries. It deliberately omits private environment variables,
tokens, and full file paths, so it is safe to share.

## Expected LIMITED Behavior (Not Bugs)

These are intentional and should not be reported as defects:

- Runtime is `FROZEN`; Node.js/npm/Python/Git are not included.
- QuickJS and Duktape report deferred / unavailable.
- Native binary packages are not supported.
- Storage commands need a linked folder; unlinked storage shows `LIMITED`.
- `qa-status` showing `READY WITH LIMITATIONS` is acceptable.
- Direct app-bin execution may be blocked by Android (use `sh $TERMODE_BIN/...`
  or `run-tool`).

## Release Blockers (Please Report Immediately)

- crash on launch
- REAL PTY cannot start (no working shell)
- commands cannot be typed into the terminal
- package manager broken (install/remove/doctor fails)
- session restore crash after force-close/reopen
- unsafe file path issue (a command escapes Termode home or deletes a
  protected file)
- helper reload leaks (reload markers or duplicate prompts appear in output)
- app freezes on normal command output
