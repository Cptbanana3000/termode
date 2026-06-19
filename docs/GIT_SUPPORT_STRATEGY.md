# Git Support Strategy (v0.45)

v0.45 prepares the **first real-tool path** for Git on top of the v0.44 binary
package installer prototype. It is a feasibility / installer-path milestone:
it determines how Git can be safely installed, detected, wrapped, verified, and
exposed — **without faking Git**. Termode only claims Git is installed if a real
`git` binary (or compatible implementation) exists and `git --version` succeeds.

**Honest result for this build:** no safe Git binary artifact is bundled, so Git
is reported as **planned / not installed** everywhere, and the install path
refuses safely. Real Git execution requires a future vendored/built/trusted,
ABI-matched, checksum-verified package artifact (targeted for v0.46).

## Why Git Is the First Real Tool Target

- It is the most-requested developer tool and unlocks real project workflows
  (clone, commit, branch, history) inside Termode.
- It is self-contained enough to be a good first real binary package, while
  still exercising the full install/verify/shim/run pipeline.

## Why Git Is Harder Than hello-bin

- `hello-bin` is a tiny built-in script with a known checksum. Git is a real
  native binary (or a large multi-file install) that must match the device ABI.
- Git may depend on supporting libraries, certificates, and a writable,
  exec-capable location — none of which app-private storage guarantees.
- Verifying Git means actually running `git --version`, not just checking a file.

## Why Termode Must Not Fake Git

- A fake `git` script that prints a version or pretends to work would mislead
  users and corrupt real repositories. Termode's value is honesty.
- All Git status/doctor/version commands report the true state. `bin-which git`
  reports "not found" when Git is absent. No fake `git` command is created.

## Android ABI Concerns

- A Git binary must match the device ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`,
  `x86`). `runtime-abi` reports the current ABI; install must verify it.

## App-Private Executable Limitations

- App-private files may be mounted no-exec; direct execution can fail with
  permission errors. A future Git package may need an exec-capable strategy
  (e.g. running through the shell from a permitted location) rather than
  assuming `chmod +x` is enough.

## Dependency Concerns

- Real Git may need shared libraries, a CA bundle, and a HOME/config layout.
  The package manifest must capture every owned file and its checksum.

## Possible Future Git Sources

- a vendored, prebuilt Git artifact bundled with the app (verified at build time)
- a Termode-built Git package for supported ABIs
- a trusted, signed runtime package from a Termode-controlled registry

Never: runtime internet downloads, arbitrary device paths, the Downloads
folder, blindly copied Termux binaries, or unsigned/unverified archives.

## Package Manifest Requirements

A Git runtime package manifest must declare: name, version, kind, ABI, command,
entrypoints, and every file with a SHA-256 checksum and byte length. The
installer validates the manifest, the ABI, and each checksum before installing.

## Checksum / Signature Expectations

- Every file is SHA-256 verified on install and re-verified by
  `runtime-pkg verify git`. A future signed registry can add signature checks.

## Install Layout Under TERMODE_PREFIX

- binaries/shims under `TERMODE_PREFIX/bin` (already first on PATH)
- support files under `TERMODE_PREFIX/lib`, `TERMODE_PREFIX/share`
- package metadata under `TERMODE_PREFIX/var/termode/runtime-packages/installed.json`

## Wrapper / Shim Strategy

- The `git` shim lives inside `TERMODE_PREFIX/bin` and points only to owned
  runtime-package files. It never executes unknown external files.
- If Android blocks direct exec, the shim uses a safe shell/native strategy.
- `bin-which git` reports found only when Git is actually installed.
- `shim-list` shows `git` only if installed; otherwise it is labeled planned,
  not active.

## Verification Strategy Using `git --version`

- Git is considered AVAILABLE only after install verification passes AND
  `git --version` runs successfully. Until then it is PLANNED / NOT INSTALLED.

## Future Commands to Test

```sh
git --version
git init
git status
git add
git commit
git log
```

`git-test-plan` lists the full workspace test sequence; it is blocked until a
Git package artifact exists.

## What v0.45 Does and Does Not Support

Supported now:
- honest Git capability commands: `git-status`, `git-info`, `git-plan`,
  `git-version`, `git-doctor`, `git-test-plan`
- a safe `git` placeholder that guides the user when Git is not installed
- `runtime-pkg` awareness of a planned `git` package (info/available)
- a safe, refusing `runtime-pkg install git` (no artifact = no install)
- `runtime-install` / `toolchain` / `dev-doctor` integration that reports Git
  as feasibility/planned

Not supported yet:
- a real `git` binary or `git --version`
- `git init` / `status` / `add` / `commit` / `log`
- any Git download, fake Git script, or unverified install

## v0.46 Update: Artifact Pipeline + Execution Probe

v0.46 implements the install/verify/shim/run pipeline and a `git --version`
execution probe (`git-exec-probe`), plus a trusted-artifact registry and Git
manifest validation. No Git artifact is bundled, so Git remains `UNAVAILABLE`
and the installer refuses safely. The exact artifact requirements are in
[Git Artifact Contract](GIT_ARTIFACT_CONTRACT.md). Real artifact
acquisition/build is v0.47.

## v0.47 Update: Acquisition / Build Pipeline

v0.47 adds the acquisition/build pipeline without bundling Git. The repo now
contains:

- `docs/GIT_ARTIFACT_ACQUISITION.md`
- `docs/GIT_BUILD_PIPELINE.md`
- `tools/runtime-artifacts/git/manifest.template.json`
- placeholder ABI/checksum directories for future trusted payloads

`git-artifact pipeline`, `git-artifact requirements`, `git-artifact sources`,
and `git-artifact next` explain the path from template to verified artifact.
`TEMPLATE_ONLY` is not installable, and Termode still refuses `runtime-pkg
install git` until a real trusted artifact is bundled and `git --version`
passes on device.
