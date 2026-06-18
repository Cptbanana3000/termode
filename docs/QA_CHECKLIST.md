# Termode QA Checklist

Use this checklist for v0.36 beta readiness testing on Android.

For the v0.37 device bug bash, start with:

- `qa-run`
- `qa-status`
- `qa-report`
- `bug-report`

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
