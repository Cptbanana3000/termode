# Git Runtime Artifact Staging

This directory describes where a future trusted Git artifact will live.

Expected layout:

```text
tools/runtime-artifacts/git/
  manifest.template.json
  checksums/
  arm64-v8a/
    manifest.json
    files/
  armeabi-v7a/
    manifest.json
    files/
  x86_64/
    manifest.json
    files/
```

v0.52 ships only templates, trusted production/acquisition checks, and the
host-side NDK build preflight
docs. There is no executable Git payload here, and the template is not
installable. A project-side candidate
uses the per-ABI `manifest.json` plus `files/` directory shown above.

A real artifact must include:

- a validated `manifest.json`
- relative file paths only
- SHA-256 checksums for every file
- a supported ABI
- `source` set to `termode-built` or `termode-vendored`
- a working `git --version` smoke test before release

Validate a candidate with:

```sh
git-artifact bundle-check
git-artifact production-status
```
