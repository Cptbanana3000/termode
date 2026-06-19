# Verify Git Artifact

After a real trusted artifact is staged, run:

```sh
git-artifact bundle-check
runtime-pkg install git
git-version
git-exec-probe
git-smoke-test
runtime-pkg verify git
git-doctor
git-workspace-smoke-plan
```

Expected before a real payload exists:

- `git-artifact bundle-check` reports `TEMPLATE_ONLY` or `UNAVAILABLE`
- `runtime-pkg install git` refuses safely
- `git-version` does not fake output
- `git-exec-probe` says Git is not installed

Expected after a real payload exists:

- bundle check is `AVAILABLE`
- install succeeds only after checksum verification
- `git --version` prints a real Git version
- failed install rolls back copied files
