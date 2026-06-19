# Runtime Expansion Architecture

Termode is growing from a standalone Android terminal into a guided dev
environment with real toolchains. The current architecture is intentionally
incremental:

- v0.42 defined the runtime expansion planning surface.
- v0.43 made prefix, PATH, environment, bin discovery, and REAL PTY environment
  injection usable.
- v0.44 adds the first safe runtime package installer prototype.

See [Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md) for the current
environment layer, and
[Binary Package Installer Prototype](BINARY_PACKAGE_INSTALLER_PROTOTYPE.md) for
runtime package metadata, checksum validation, and `hello-bin`.

## Why Termode Is Not Bundling Node/Git/Python Yet

- Correctness before size: large runtime bundles need a controlled prefix, PATH,
  metadata, checksums, ABI checks, and doctors.
- Android execution constraints: app-private files may not execute like desktop
  Linux files, so Termode must support safe host interception and shims.
- Safety: real runtime packages need provenance, update policy, checksum
  validation, and removal tracking.
- Honesty: Termode will not claim Git/Node/npm/Python support until those
  commands actually work.

## Layered Plan

1. Controlled app-private prefix.
2. Deterministic PATH and environment injection.
3. Runtime package metadata model.
4. ABI and capability checks.
5. Safe install, verify, remove, repair, shim, and doctor flow.
6. Real toolchains.

v0.44 reaches step 5 with a built-in prototype package only. Real Git,
Node.js, npm, and Python remain future milestones.

## Prefix

Termode uses the app-private `files/usr` directory as `TERMODE_PREFIX`. This is
deliberately unified with the existing script-package prefix so
`TERMODE_BIN=files/usr/bin` stays stable and existing `pkg` commands and silent
helper reload keep working.

```text
$TERMODE_PREFIX/  # files/usr
  bin/
  lib/
  share/
  tmp/
  var/
    termode/
      runtime-packages/
        installed.json
        cache/
          manifests/
  packages/
  runtime/
  toolchains/
    git/
    node/
    python/
$TERMODE_HOME/
  projects/
  cache/
  config/
```

## PATH And Environment

REAL PTY receives:

- `TERMODE_HOME`
- `TERMODE_PREFIX`
- `TERMODE_BIN`
- `TERMODE_WORKSPACES`
- `TERMODE_TMPDIR`
- `TERMODE_CACHE`
- `TERMODE_CONFIG`
- `PATH`
- `HOME`
- `TMPDIR`
- `TERM`

PATH puts `TERMODE_PREFIX/bin` first, then Android/system shell paths.

## Runtime Package Metadata

Runtime package entries carry:

- name
- version
- description
- kind
- ABI
- entrypoints
- owned files
- SHA-256 checksums
- source
- install time
- status

v0.44 stores metadata at:

```text
$TERMODE_PREFIX/var/termode/runtime-packages/installed.json
```

The prototype installer writes metadata atomically with a temporary file and
rename, handles missing/corrupt metadata without crashing, and removes only
files recorded as owned by a package.

## v0.44 Prototype

The only installable runtime package in v0.44 is:

```text
hello-bin
```

It is a tiny built-in script-tool that prints a known message. It proves the
installer model without adding real binary runtime support.

## Future Roadmap

- v0.45 Git Support
- v0.46 Git Artifact Execution Probe
- v0.47 Git Artifact Acquisition / Build Pipeline
- v0.48 Verified Git Artifact Bundle / Smoke Test
- v0.49 Git Artifact Build / arm64-v8a Production
- v0.50 Git Artifact Production / Trusted Build
- v0.51+ Node.js / npm / Python / Dev Stack Presets
- v0.52 Full Terminal QA
- v0.53 Complete Termode Beta

CalypsoIDE integration stays out of scope until the standalone Termode beta is
stable.

## v0.45 Update: Git Feasibility

The first real tool target is Git. v0.45 proves the install/verify/shim path and
adds `git-*` capability commands, but ships no Git artifact (planned, not
installed; the installer refuses safely). See
[Git Support Strategy](GIT_SUPPORT_STRATEGY.md).
