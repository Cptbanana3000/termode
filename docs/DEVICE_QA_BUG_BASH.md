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

## Bug Reports

Run:

```sh
bug-report
qa-report
```

Copy the output into the issue. Do not include screenshots or logs containing
tokens, private repository URLs, or secrets.
