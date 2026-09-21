# Git Local Workflow Status - Termode v0.65

## Phase Summary

**v0.65: Local Git UX Polish** expands Termode's verified Git support from the v0.64 foundation (`git --version`, `git init`, `git status`) to a comprehensive offline local Git development workflow.

The immutable arm64-v8a Git 2.44.0 binary executes from Android's `applicationInfo.nativeLibraryDir` (`libtermode_git_exec.so`) while `TERMODE_PREFIX/usr/bin/git` remains the stable logical command path.

## Supported Local Commands

The following commands are enabled, verified, and mapped through the native execution bridge and PTY shell:

| Category | Commands |
| :--- | :--- |
| **Information** | `git --version`, `git -v`, `git --help`, `git help` |
| **Repository Setup** | `git init`, `git config` (local and `--global`) |
| **Staging & Worktree** | `git status`, `git add`, `git rm`, `git mv`, `git reset`, `git diff`, `git show`, `git restore`, `git clean` |
| **History & Branches** | `git commit`, `git log`, `git branch`, `git checkout`, `git switch`, `git tag`, `git merge`, `git stash` |

## Deferred Remote Operations

The following network-dependent commands remain explicitly deferred until `libcurl` and `OpenSSL` / TLS dependencies are staged in a future milestone:

- `git clone`
- `git fetch`
- `git pull`
- `git push`
- `git remote`
- `git submodule`

When a user attempts any of these commands, Termode returns a clean explanation:
```
Remote Git operations (<command>) are deferred.
v0.65 supports offline local Git workflows only.
```

## User Identity & Configuration Guidance

Git requires `user.name` and `user.email` before a commit can be created. In v0.65:
- `git config` reads and writes configuration files stored under `files/home/.gitconfig` or `files/home/config/git/config` (`XDG_CONFIG_HOME`).
- If `git commit` is attempted before configuring an identity, Termode detects Git's warning and outputs a helpful tip:
  ```
  Tip: Configure your Git identity in Termode:
    git config --global user.name "Your Name"
    git config --global user.email "you@example.com"
  ```

## Workspace Resolution

- When operating inside a Termode workspace (e.g. via `workspace-cd <project>`), `git` commands executed from the terminal automatically resolve to that workspace directory (`preferredWorkingDirectory`), creating repositories, staging files, and recording commits cleanly within the workspace.

## Test Verification

- Unit test suite: `test/git_local_workflow_test.dart`
- Full test suite: **566 passing tests across 35 test suites** (0 failures).
