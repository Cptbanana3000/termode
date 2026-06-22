# Git Source Staging Rules (v0.54)

This document specifies the rules for staging Git source code in the Termode workspace.

## Staging Rules
1. **Pinned Versioning**: Source code must correspond exactly to the pinned version target (currently `2.44.0`). Do not use "latest" or unpinned source versions.
2. **SHA-256 Checksum**: Any source archive file (`.tar.xz`, `.tar.gz`) must have its SHA-256 checksum verified and recorded in the build manifest.
3. **Provenance Note**: Staged source trees must include a `SOURCE_PROVENANCE.md` detailing the origin, downloaded URL, date, and reviewer's signature.
4. **No Sandbox Leaks**: Do not reference paths in the user's personal `Downloads` folder or other system-specific paths outside the workspace.
5. **No Unverified Zips**: Do not extract or use unofficial zip/tarballs from random mirrors.
6. **No Fake Placeholders**: Do not create empty files or dummy files pretending to be real source files.
7. **No App-Runtime Downloads**: The Termode Android app never downloads source archives or binaries at runtime.
8. **Git Commit Policy**: Large source archives and complete extracted source trees should **not** be committed to the repository (add them to `.gitignore` if needed) to keep repository size manageable.
9. **Verification Prerequisite**: The local build manifest `build-inputs.json` can only reference the staged files after they pass all check and verification scripts. Example or candidate manifests (such as `build-inputs.candidate.json`) do not bypass these staging checks.
