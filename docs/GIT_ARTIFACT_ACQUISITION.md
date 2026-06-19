# Git Artifact Acquisition (v0.47, extended in v0.48-v0.50)

Termode can only ship real Git after a trusted artifact is acquired or built.
v0.47 creates the acquisition path, but does not bundle Git. v0.48 adds
project-controlled bundle validation and a smoke-test path for a future
artifact. v0.49 prepares the arm64-v8a production artifact layout and helper
pipeline. v0.50 completes the trusted production pipeline while still keeping
Git unavailable until a real payload exists.

See [Git Artifact Production Status](GIT_ARTIFACT_PRODUCTION_STATUS.md) and
[Git Trusted Build](GIT_TRUSTED_BUILD.md).

Allowed sources:

- `termode-built`: built by the Termode project from auditable source inputs
- `termode-vendored`: vendored by Termode with license, provenance, manifest,
  checksums, and ABI compatibility documented

Rejected sources:

- random internet binaries
- copied Termux app binaries
- user-selected archives
- runtime downloads
- files with missing checksums or unsafe paths

Required artifact evidence:

- manifest with `name: git`, `kind: native-tool`, and `command: git`
- supported ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`, or `all`)
- relative entrypoint such as `bin/git`
- SHA-256 checksum for every payload file
- source URL or reproducible build note
- license review
- `git --version` verification
- smoke tests listed before release

Current v0.48 state:

- acquisition documents: present
- build/staging layout: present
- manifest template: present
- project artifact validation: present
- install rollback path: present
- `git --version` smoke gate: present
- arm64-v8a production layout: present
- real Git artifact: not bundled
- install state: blocked until verified artifact exists

Use `git-artifact pipeline`, `git-artifact requirements`,
`git-artifact bundle-status`, `git-artifact bundle-check`, and
`git-artifact smoke-plan` inside Termode for the device-facing summary.
