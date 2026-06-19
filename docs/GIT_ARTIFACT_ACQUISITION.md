# Git Artifact Acquisition (v0.47)

Termode can only ship real Git after a trusted artifact is acquired or built.
v0.47 creates the acquisition path, but does not bundle Git.

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

Current v0.47 state:

- acquisition documents: present
- build/staging layout: present
- manifest template: present
- real Git artifact: not bundled
- install state: blocked until verified artifact exists

Use `git-artifact pipeline`, `git-artifact requirements`, and
`git-artifact next` inside Termode for the device-facing summary.
