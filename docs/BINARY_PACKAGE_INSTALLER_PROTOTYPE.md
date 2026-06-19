# Binary Package Installer Prototype

Termode v0.44 adds the first safe installer mechanism for future
binary/runtime packages. It does not add Git, Node.js, npm, Python, compilers,
QuickJS, Duktape, large binary assets, external downloads, or arbitrary archive
extraction.

The milestone proves the installer shape with one built-in prototype package:

```sh
runtime-pkg available
runtime-pkg install hello-bin
hello-bin
runtime-pkg verify hello-bin
runtime-pkg remove hello-bin
```

`hello-bin` prints:

```text
Hello from Termode binary package prototype.
```

It is intentionally a tiny script-tool, not a native runtime. Termode treats it
as a stand-in for the future binary package flow so metadata, checksums,
prefix/bin integration, command discovery, doctors, and removal behavior can be
tested safely before real runtime packages arrive.

## Runtime Package Model

Runtime package metadata supports:

- `name`
- `version`
- `description`
- `kind`
- `abi`
- `entrypoints`
- `files`
- `sha256`
- `installed_at`
- `source`
- `status`

Supported package kinds are:

- `shim`
- `script-tool`
- `native-tool-planned`
- `runtime-planned`

v0.44 only installs the built-in `hello-bin` package. Unknown package names are
rejected.

## Metadata Layout

Runtime package metadata lives under the Termode prefix:

```text
$TERMODE_PREFIX/
  bin/
    hello-bin
  var/
    termode/
      runtime-packages/
        installed.json
        cache/
          manifests/
  share/
    termode/
      runtime-packages/
```

The prefix is the same `files/usr` prefix used by existing script packages, so
`TERMODE_BIN` remains `files/usr/bin` and package helper reload behavior stays
compatible.

Metadata writes use a temporary file and rename flow. Missing metadata is
recreated. Corrupt metadata falls back to an empty package set and can be
repaired with:

```sh
runtime-pkg repair
```

Repair recreates metadata structures. It does not reinstall packages and does
not delete unknown files.

## Manifest And Checksum Validation

The prototype manifest validates:

- package name
- package kind
- command name
- supported ABI, currently `all` for `hello-bin`
- relative install paths
- SHA-256 checksum values

Termode rejects:

- absolute paths
- path traversal
- empty or unsafe command names
- unknown package names
- files outside `TERMODE_PREFIX`
- invalid checksums

After writing `hello-bin`, Termode re-hashes the installed file and compares it
with the manifest SHA-256 before recording metadata.

## Prefix, PATH, Bin, And Shim Integration

`hello-bin` installs into:

```text
$TERMODE_PREFIX/bin/hello-bin
```

That means:

```sh
bin-list
bin-which hello-bin
shim-list
```

can discover it after installation. In REAL PTY mode, `hello-bin` is handled by
Termode host command interception so Android private-storage executable limits
do not block the prototype. The installed file is still placed in the prefix bin
for parity with future runtime packages.

## Commands

```sh
runtime-pkg
runtime-pkg help
runtime-pkg list
runtime-pkg available
runtime-pkg info hello-bin
runtime-pkg install hello-bin
runtime-pkg remove hello-bin
runtime-pkg verify hello-bin
runtime-pkg status
runtime-pkg doctor
runtime-pkg repair
runtime-abi
hello-bin
```

`runtime-install status`, `runtime-install list`, `runtime-install doctor`,
`toolchain-status`, `toolchain-doctor`, `dev-doctor`, `status`, `build-info`,
and beta candidate output now mention that the runtime package installer is
prototype ready while Git/Node/npm/Python remain planned.

## What Is Not Included

v0.44 does not include:

- Git
- Node.js
- npm
- Python
- compilers
- native binary package repositories
- untrusted archive extraction
- internet downloads
- arbitrary user-provided runtime packages

Missing Git/Node/npm/Python is expected and does not make beta readiness fail.

## Safety Rules

- Only built-in prototype manifests are accepted.
- Only controlled relative paths under `TERMODE_PREFIX` are allowed.
- Removal deletes only files recorded as owned by the installed runtime package.
- Shared directories are never removed.
- Unknown files are never deleted by repair.
- Prototype packages do not execute unknown binaries.

## Roadmap

v0.44 proves the installer mechanics. The next milestone is:

```text
v0.45 Git Support
```

Future milestones can reuse the same prefix, metadata, checksum, ABI, bin, and
shim model for larger runtimes.

## Next: Git (v0.45)

v0.45 applies this installer pattern to Git as a feasibility / installer-path
milestone. `runtime-pkg` now knows a planned `git` package, but ships no Git
artifact, so `runtime-pkg install git` refuses safely and Git is reported as
planned/not installed. Real, verified Git install/execution arrives in v0.46.
See [Git Support Strategy](GIT_SUPPORT_STRATEGY.md).

## v0.46 Update: Git Artifact Pipeline

v0.46 extends this installer toward real tools with a trusted-artifact registry
(`RuntimeArtifactRegistryService`), Git manifest validation, and a
`git --version` execution probe. No Git artifact is bundled yet, so installs
still refuse safely. See [Git Artifact Contract](GIT_ARTIFACT_CONTRACT.md).
