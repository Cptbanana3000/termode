# Runtime Expansion Architecture (v0.42)

Update: v0.43 implements the first runtime-environment layer from this plan.
See [Prefix / PATH / Environment](PREFIX_PATH_ENVIRONMENT.md) for the current
prefix, PATH overlay, environment injection, bin discovery, and shim planning
commands.

This document describes how Termode will grow from a strong standalone terminal
into a guided dev environment with real toolchains (Git, Node.js, npm, Python,
editors). v0.42 builds the **architecture and planning surface only** — it does
not install, download, or execute any external runtime.

Termode's long-term direction: be a complete standalone Android terminal/dev
environment first (easier and more guided than Termux), and only later be
embedded into CalypsoIDE as a plug-and-play terminal/runtime engine.

## Why Termode Is Not Bundling Node/Git/Python Yet

- **Correctness before bulk.** Dropping large prebuilt binaries in without a
  controlled prefix, PATH strategy, and capability checks produces a fragile,
  Termux-like "it sometimes works" experience. Termode wants guided and honest.
- **Android execution constraints.** App-private files are often mounted
  no-exec or restricted; direct execution of `files/usr/bin/<binary>` can fail
  with permission errors. A runtime layer must account for this rather than
  assume desktop Linux.
- **Size, updates, and safety.** Real runtimes need source/provenance,
  sandboxing, timeouts, cache management, and update policies. Those are
  architecture decisions, not a quick bundle.
- **Honesty.** Termode will not claim to support Node/npm/Git/Python until they
  actually run.

## Why Architecture Comes First

A clean runtime layer needs, in order:

1. a controlled, app-private **prefix** layout
2. a deterministic **PATH** and **environment** strategy
3. a **package/runtime metadata** model
4. **capability checks** (ABI, exec, write access)
5. a safe **install flow** with shims and doctors
6. only then, real toolchains

v0.42 delivers (1) the prefix layout and planning service, and the planning
commands for (2)–(5). The real install engine begins in later milestones.

## Android Execution Limitations

- App-private storage may block execution; the installer will need to handle
  exec permissions and possibly an exec-friendly location.
- ABI matters: binaries must match the device ABI (e.g. `arm64-v8a`).
- No root, no system package manager, no `/usr` write access.
- Full-screen TUI programs need mature PTY rendering.

## App-Private Prefix Idea

Termode manages **its own controlled prefix** under `TERMODE_HOME`. This is not
a full Linux distribution and not a system prefix — it is Termode's sandboxed
area that it fully controls and can reset safely. It is intentionally separate
from the existing script-package directory (`files/usr`) so this work cannot
break the current package manager.

## Termode Prefix Layout

```
$TERMODE_HOME/
  usr/
    bin/
    lib/
    share/
    tmp/
    var/
    packages/
    runtime/
    toolchains/
      git/
      node/
      python/
  workspaces/
  cache/
  config/
```

Inspect and create it with:

```sh
prefix-info
prefix-init
prefix-doctor
path-info
env-info
```

`prefix-init` is idempotent and never deletes user files.

## PATH Strategy

Planned PATH order (not yet applied to the live shell):

1. `$TERMODE_HOME/usr/bin` (Termode-installed tools and shims)
2. bundled helper scripts
3. Android/system shell paths (`/system/bin`, etc.)

Termode will only mutate the live shell PATH once it is safe and tested
(targeted for the v0.43 Prefix / PATH / Environment System milestone).

## Environment Variable Strategy

| Variable             | Meaning                                   |
| -------------------- | ----------------------------------------- |
| `TERMODE_HOME`       | app-private home (stays private)          |
| `TERMODE_PREFIX`     | `$TERMODE_HOME/usr`                        |
| `TERMODE_BIN`        | `$TERMODE_PREFIX/bin`                      |
| `TERMODE_WORKSPACES` | `$TERMODE_HOME/workspaces`                 |
| `TMPDIR`             | `$TERMODE_PREFIX/tmp`                      |

`env-info` prints the planned values. The live runtime environment is unchanged
in v0.42.

## Package Metadata Strategy

Runtime/toolchain entries will carry: name, display name, ABI requirements,
source/provenance, checksum, dependencies (e.g. npm requires node), install
location under the prefix, and the command shim to expose. This extends the
existing script-package metadata model rather than replacing it.

## Future Binary Package Model

- prebuilt, ABI-matched, checksum-verified artifacts
- installed into `$TERMODE_PREFIX` with a recorded manifest
- exposed via shims in `$TERMODE_BIN`
- removable and repairable (like the current `pkg` flow)
- no fragile, unverified downloads

## Toolchain Capability Checks

Before any real install, Termode will verify: device ABI, exec capability in
the target location, available space, write access, and dependency order
(Node before npm). The planning commands today are:

```sh
toolchain-status
toolchain-list
toolchain-info <name>
toolchain-plan
toolchain-doctor
```

## Future Install Flow

```sh
runtime-install list
runtime-install plan <tool>
runtime-install status
runtime-install doctor
```

Planned install sequence (per tool): verify ABI → select compatible source →
install into prefix → add command shim → run `<tool> --version` → run a doctor.
Guided presets will wrap this:

```sh
dev-setup list
dev-setup plan web
dev-doctor
```

In v0.42 these are **planning-only**. Nothing is downloaded or executed.

## Security / Safety Rules

- Never escape `TERMODE_HOME`.
- Never delete user files during prefix init.
- No execution of unverified binaries.
- No fragile or unattended downloads.
- ABI and checksum verification before any future install.
- Honest status: planned vs installed is always clear.

## CalypsoIDE Integration (Later)

Only after Termode is strong as a standalone terminal/dev environment will it be
integrated into CalypsoIDE as a plug-and-play terminal/runtime engine. The
controlled prefix, PATH/env strategy, and capability checks defined here are
what make that embedding clean and predictable. This is explicitly out of scope
until the standalone beta is complete.
