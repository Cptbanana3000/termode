# Git On-Device Smoke Test - v0.63

## v0.64 result

PASS on an Android 16 arm64-v8a tablet (SM-X510). `runtime-pkg install git`
validated the extracted native-library payload and reported
`git version 2.44.0`. `git-version` and direct REAL PTY
`git --version` returned the same real output. `git-smoke-test` passed
version, init, and status in `TERMODE_PREFIX/usr/tmp/git-smoke` and reported
`HEALTHY`. Remote Git remained deferred and no network action occurred.

After installing an arm64 debug APK on an authorized Android device:

1. Run runtime-pkg install git.
2. Run bin-which git and confirm the app-private prefix path.
3. Run git-version and git --version; both must execute the installed ELF.
4. Run git-smoke-test.

The smoke test creates an app-private temporary workspace and runs only:
git --version, git init, and git status. It does not perform network access,
clone, fetch, pull, push, commits, or dependency downloads.

Record the exit code and real stderr for any failure. Classify permission,
ABI/ELF, linker/shared-library, PATH, working-directory, HOME/environment, or
unknown execution failures honestly. Never substitute hardcoded output.

## v0.63 result

On Android 16, the packaged ELF reports git version 2.44.0 when run from
Android's executable ADB staging area. The same bytes are denied execution from
Termode's writable app-private files/usr/bin path. runtime-pkg rolls back, so
the remaining local smoke checks are blocked. This is Path B and is carried to
v0.64 Git On-Device Execution Fixes.
