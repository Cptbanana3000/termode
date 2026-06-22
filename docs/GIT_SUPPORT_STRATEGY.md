# Git Support Strategy (v0.45, extended through v0.57)

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
acquisition/build is v0.47, verified bundle/smoke validation is v0.48, and
arm64-v8a production pipeline preparation is v0.49, and trusted production
pipeline completion is v0.50.

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

## v0.48 Update: Verified Bundle / Smoke Path

v0.48 validates a project-controlled candidate artifact when present:

- `git-artifact bundle-status`
- `git-artifact bundle-plan`
- `git-artifact bundle-check`
- `git-artifact smoke-plan`

The installer revalidates before copying, writes only manifest-owned files into
`TERMODE_PREFIX`, rechecks copied SHA-256 values, runs `git --version`, and
rolls back on any failure. This still does not bundle Git; missing Git remains
planned/not installed, not unhealthy.

## v0.49 Update: arm64-v8a Production Pipeline

v0.49 chooses the honest no-artifact path because no trusted Git source bundle
or project-controlled payload exists in the checkout. It adds:

- `docs/GIT_ARTIFACT_BUILD_STATUS.md`
- `docs/GIT_ARM64_ARTIFACT_PIPELINE.md`
- `tools/git-build/`
- `tools/runtime-artifacts/git/arm64-v8a/manifest.json.example`
- `tools/runtime-artifacts/git/arm64-v8a/files/README.md`

Git remains unavailable until a trusted payload passes `git-artifact
bundle-check`, `runtime-pkg install git`, and real `git --version`.

## v0.50 Update: Trusted Production Pipeline

v0.50 selects Path B: reproducible production pipeline completed, no real Git
payload yet. Git remains unavailable and not installed. The next step is a real
trusted payload plus Android `git --version` verification.

See [Git Artifact Production Status](GIT_ARTIFACT_PRODUCTION_STATUS.md) and
[Git Trusted Build](GIT_TRUSTED_BUILD.md).

## v0.51 Update: NDK Source-Build Environment

The project now detects Android SDK/NDK and host prerequisites, provides a safe
arm64-v8a preflight, and records the source/dependency build plan. Path B was
selected: the NDK is present, but reviewed source inputs are absent. Git stays
unavailable and no runtime safety rule is weakened. See
[Git NDK Build Status](GIT_NDK_BUILD_STATUS.md) and
[Git NDK Source Build](GIT_NDK_SOURCE_BUILD.md).

## v0.52 Update: Source And Dependency Acquisition

v0.52 adds explicit build-input examples, schema guidance, safe path and
checksum validation, Git source verification, and staged dependency reporting.
No script downloads inputs and the template cannot be treated as real inputs.
Path B remains selected until reviewed sources and Perl are available. See
[Git Source Acquisition Status](GIT_SOURCE_ACQUISITION_STATUS.md),
[Git Source Acquisition](GIT_SOURCE_ACQUISITION.md), and
[Git Dependency Plan](GIT_DEPENDENCY_PLAN.md).

## v0.53 Update: Git Source + Dependency Preparation

v0.53 selects Git version 2.44.0, documents the host Perl build prerequisite,
defines the Stage 1 zlib minimal dependency strategy, and prepares build manifest templates.
No real source payload is staged yet and Git remains honestly unavailable. See
[Git Source + Dependency Preparation Status](GIT_SOURCE_DEPENDENCY_PREP_STATUS.md) and
[Git Source Version Decision](GIT_SOURCE_VERSION_DECISION.md).

## v0.54 Update: Git Build Prerequisite Resolution

v0.54 focuses on host-side build readiness. It resolves and narrows host-side prerequisites (Perl detection, staging rules for GPL-2.0-only Git sources, zlib-1.3.1 dependency strategies, and candidate build-inputs json structures). Git remains honestly unavailable until real verified inputs are promoted. See [Git Build Prerequisite Status](GIT_BUILD_PREREQUISITE_STATUS.md).

## v0.55 Update: Git Prerequisite Acquisition / Source Staging

v0.55 focuses on staging official source archives on the host. It downloads git-2.44.0.tar.xz and zlib-1.3.1.tar.xz to the tools/git-build/sources/ staging folder, verifies their SHA-256 checksums, and promotes build-inputs.json. Since Perl is still missing from the host environment, the overall pipeline remains PARTIAL and Git is unavailable in-app. See [Git Build Prerequisite Status](GIT_BUILD_PREREQUISITE_STATUS.md).

## v0.56 Update: Git Perl Resolution / arm64 Build Readiness

v0.56 focuses on resolving the host Perl dependency via manual setup instructions, hardening host environment checks, introducing the `git-build-readiness` command and `print_build_readiness.dart` script, and preparing for the first arm64 NDK compilation attempt. Since Perl is still missing from the host environment, the status remains PARTIAL. See [Git Perl Resolution Status](GIT_PERL_RESOLUTION_STATUS.md) and [Git Build Prerequisite Status](GIT_BUILD_PREREQUISITE_STATUS.md).

## v0.57 Update: Git Perl Setup / Build Readiness Finalization

v0.57 finalizes host-side Perl prerequisite checking, error handling, manual setup docs, and bumps all in-app diagnostics commands, docs, and version configurations to v0.57. Since Perl is still missing on the Windows host, the status remains PARTIAL. See [Git Build Readiness Final Status](GIT_BUILD_READINESS_FINAL_STATUS.md) and [Git Build Prerequisite Status](GIT_BUILD_PREREQUISITE_STATUS.md).

