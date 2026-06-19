# Git Runtime Artifact Staging

This directory describes where a future trusted Git artifact will live.

Expected layout:

```text
tools/runtime-artifacts/git/
  manifest.json
  manifest.template.json
  checksums/
  arm64-v8a/
  armeabi-v7a/
  x86_64/
```

v0.47 ships only the template and placeholders. There is no executable Git
payload here, and the template is not installable.

A real artifact must include:

- a validated `manifest.json`
- relative file paths only
- SHA-256 checksums for every file
- a supported ABI
- `source` set to `termode-built` or `termode-vendored`
- a working `git --version` smoke test before release
