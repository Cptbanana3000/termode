# Git Artifact Contract (v0.46)

This contract defines what a **real, installable Git package artifact** must
look like for Termode to install, verify, expose, and run it. It is the trust
boundary for real native tools. Termode only reports Git as installed/available
when a verified artifact exists **and** `git --version` succeeds.

**Status in this build:** no Git artifact is bundled, so Git is `UNAVAILABLE`
and not installable. The pipeline (registry, manifest validation, install path,
execution probe) is implemented and honest; it simply has nothing to install.

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
4. files install under the prefix
5. the `git` shim registers
6. `git --version` runs successfully (`git-exec-probe` HEALTHY)

If verification fails after a partial install, the install is rolled back and
Git is **not** marked installed.

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
