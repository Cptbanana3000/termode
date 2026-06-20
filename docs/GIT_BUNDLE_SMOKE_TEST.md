# Git Bundle Smoke Test (v0.48, extended through v0.51)

v0.48 adds the verified Git bundle and smoke-test path. It does not bundle a
real Git artifact yet. v0.49 adds the arm64-v8a production artifact layout and
build pipeline docs. v0.50 adds the trusted production gate, but still ships no
trusted payload.

## Current Result

- real Git artifact: not bundled
- project candidate validation: implemented
- install rollback: implemented
- `git --version` smoke gate: implemented
- Git status in normal APKs: `UNAVAILABLE` / not installed
- Git status in source checkouts with only the template: `TEMPLATE_ONLY`

Missing Git is expected and does not make Termode unhealthy.

## Trusted Project Layout

A candidate artifact must live under:

```text
tools/runtime-artifacts/git/<abi>/manifest.json
tools/runtime-artifacts/git/<abi>/files/
```

For the first production target, `<abi>` is `arm64-v8a`.

The manifest must describe only safe relative files under the future runtime
prefix layout:

```text
bin/
lib/
libexec/
share/
```

Absolute paths, parent traversal, missing checksums, unsupported ABIs, and
untrusted sources are rejected.

## Commands

```sh
git-artifact bundle-status
git-artifact bundle-plan
git-artifact bundle-check
git-artifact smoke-plan
runtime-pkg install git
git-exec-probe
git-smoke-test
```

## Install / Smoke Flow

When a trusted artifact exists, `runtime-pkg install git`:

1. validates the manifest and ABI
2. verifies every artifact file exists
3. verifies every SHA-256 checksum
4. copies only manifest-owned files into `TERMODE_PREFIX`
5. rechecks copied checksums
6. runs `git --version`
7. records Git metadata only after the smoke command succeeds

If any step fails, the copied files are removed and Git remains not installed.

## Release Gate

Termode must not claim Git support until a real artifact passes:

```sh
git-artifact bundle-check
runtime-pkg install git
git-version
git-exec-probe
git-smoke-test
runtime-pkg verify git
git-doctor
```

In v0.52, the smoke test remains blocked because acquisition is defined but
trusted Git and dependency sources do not exist. The next milestone is v0.53
Git Source + Dependency Preparation.
