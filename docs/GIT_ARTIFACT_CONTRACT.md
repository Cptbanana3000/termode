# Git Artifact Contract (v0.49, productionized in v0.50-v0.51)

This contract defines what a **real, installable Git package artifact** must
look like for Termode to install, verify, expose, and run it. It is the trust
boundary for real native tools. Termode only reports Git as installed/available
when a verified artifact exists **and** `git --version` succeeds.

**Status in this build:** no real Git artifact is bundled, so Git is
`TEMPLATE_ONLY` in a source checkout or `UNAVAILABLE` in an installed APK, and
not installable. The pipeline (registry, manifest validation, project artifact
checks, install path, rollback, execution probe, arm64-v8a build docs/helpers,
and manifest templates/examples) is implemented and honest; it simply has no
verified payload to install.

## Package Identity

- name: `git`
- kind: `native-tool`
- command: `git`
- verification command: `git --version`
- workspace smoke-test command: `git init`

## Supported ABIs

A Git artifact is ABI-specific and must match the device ABI:

- `arm64-v8a`
- `armeabi-v7a` (if supported later)
- `x86_64` (if supported later)

`runtime-abi` and `git-artifact status` report the current device ABI. An
artifact whose ABI does not match the device is `INCOMPATIBLE` and not
installable.

## Manifest Format

A Git manifest is JSON with at least:

```json
{
  "name": "git",
  "version": "<semver>",
  "kind": "native-tool",
  "abi": "arm64-v8a",
  "command": "git",
  "entrypoint": "bin/git",
  "source": "termode-vendored",
  "license": "GPL-2.0",
  "files": [
    { "path": "bin/git", "sha256": "<64 hex>", "bytes": 123 }
  ]
}
```

### Required Fields

- `name` must equal `git`
- non-empty `version`
- `kind` must equal `native-tool`
- non-empty, safe `command` (`^[a-z][a-z0-9-]{0,31}$`)
- `abi` must be `all` or a supported ABI
- safe relative `entrypoint` under the prefix
- trusted `source` label
- non-empty `files`, each with a safe relative path and a valid SHA-256

## Required Files / Entrypoint

- every file path is relative and rooted under `TERMODE_PREFIX`
  (`bin/`, `lib/`, `libexec/`, `share/` only)
- the `entrypoint` is the executable Git invokes (e.g. `bin/git`)

## Checksum Requirements

- every file declares a lowercase/uppercase 64-char hex SHA-256
- the installer re-computes and matches each checksum before marking installed
- `runtime-pkg verify git` re-checks all checksums

## Install Root Under TERMODE_PREFIX

- binaries/shims: `TERMODE_PREFIX/bin`
- support files: `TERMODE_PREFIX/lib`, `TERMODE_PREFIX/libexec`, `TERMODE_PREFIX/share`
- metadata: `TERMODE_PREFIX/var/termode/runtime-packages/installed.json`

## Shim / Wrapper Rules

- the `git` shim lives at `TERMODE_PREFIX/bin/git`
- it points only to owned, installed artifact files
- no path traversal, no absolute external paths, no unknown files
- if Android blocks direct execution, the shim runs through a safe shell/native
  strategy

## Verification Strategy

Git is `AVAILABLE` only after:

1. manifest validates
2. ABI matches the device
3. every checksum matches
4. every manifest-listed artifact file exists under the trusted project or
   bundled artifact root
5. files install under the prefix
6. copied files re-hash correctly
7. the `git` shim registers
8. `git --version` runs successfully (`git-exec-probe` HEALTHY)

If verification fails after a partial install, the install is rolled back and
Git is **not** marked installed.

## v0.48 Bundle / Smoke Gate

v0.48 distinguishes a project-side candidate artifact from a bundled release
artifact. A source checkout can stage a candidate at:

```text
tools/runtime-artifacts/git/<abi>/manifest.json
tools/runtime-artifacts/git/<abi>/files/<payload paths>
```

`git-artifact bundle-check` validates the manifest, ABI, file paths, file
existence, byte counts, and SHA-256 hashes without installing. `runtime-pkg
install git` revalidates, copies only manifest-owned files into
`TERMODE_PREFIX`, runs `git --version`, and rolls back if any step fails.
An APK with no bundled artifact remains honest: Git is unavailable, not fake.

## v0.49 arm64-v8a Production Preparation

v0.49 adds the project-side `arm64-v8a` production layout, example manifest,
files placeholder, and optional helper scripts. It does not add a real payload.
See [Git arm64-v8a Artifact Pipeline](GIT_ARM64_ARTIFACT_PIPELINE.md).

## v0.50 Trusted Production Gate

v0.50 adds the production status and trusted build rules. A future artifact
must pass the production docs, manifest schema, SHA-256 validation, byte-count
validation, `runtime-pkg install git`, and real Android `git --version` before
Termode may report Git as available.

See [Git Artifact Production Status](GIT_ARTIFACT_PRODUCTION_STATUS.md) and
[Git Trusted Build](GIT_TRUSTED_BUILD.md).

## v0.51 Build Input Gate

Host build scripts and source/dependency folders do not make an artifact
available. Only `manifest.json` plus real payload files can enter registry
validation. Staging creates `manifest.candidate.json`; missing inputs,
zero-byte files, unsafe paths, ABI mismatches, and checksum mismatches remain
non-installable.

## Removal Rules

- remove only Git-owned files recorded in metadata
- remove the Git shim and Git metadata entry
- never remove shared prefix directories, `hello-bin`, or script packages

## Security Rules

- **No runtime network downloads.**
- **No arbitrary device-path imports** (no Downloads folder, no user zip).
- **No blindly copied Termux binaries.**
- **No fake `git` script** that prints a fake version.
- only artifacts from a `trustedSources` label are accepted
- corrupt metadata/manifest must never crash the app

## What Counts as a Trusted Artifact

- `termode-vendored` — a Git package vendored into the app build and verified at
  build time
- `termode-built` — a Git package built by the Termode toolchain for a supported
  ABI

Anything else (random binary, user archive, internet download) is rejected.

## Why Untrusted / Random Binaries Are Rejected

Executing an unverified binary risks the user's data and device and would make
Termode dishonest about what it ships. A wrong-ABI or tampered binary can crash
or corrupt repositories. The contract guarantees that a `git` users run is the
exact, checksum-verified artifact Termode installed.
