# Git Artifact: arm64-v8a

This directory is reserved for a future trusted `arm64-v8a` Git artifact.

Expected v0.48 candidate layout:

```text
arm64-v8a/
  manifest.json
  files/
    bin/git
```

Do not add an executable until the artifact has:

- a trusted source (`termode-built` or `termode-vendored`)
- a manifest
- checksums
- license notes
- successful `git --version` verification
