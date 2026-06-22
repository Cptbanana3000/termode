# Git Source Version Decision (v0.57)

This document details the selection and validation requirements for the Git source code in Termode.

## Selected Version Target
* **Git Version**: `2.44.0` (pinned target for v0.57)
* **Reason for Selection**: Version `2.44.0` is a stable, mature release of Git that provides full compatibility with our NDK cross-compilation target (arm64-v8a) while avoiding unnecessary complexity or experimental features introduced in newer revisions.

## Expected Source Forms & Locations
The build checkers look for Git source in one of two locations:
1. **Source Archive**:
   - Location: `tools/git-build/sources/git-2.44.0.tar.xz`
2. **Source Tree**:
   - Location: `tools/git-build/sources/git-2.44.0/`

## Verification Requirements
Any staged Git source must satisfy the following criteria before a build can proceed:
- **License**: GPL-2.0-only. The source tree must contain the standard Git license file.
- **Checksum**: The source archive must match a pre-verified SHA-256 hash.
- **Provenance**: The source tree must contain a `SOURCE_PROVENANCE.md` documenting the source's exact origin.
- **Acquisition Date**: The acquisition date must be recorded in UTC.
- **Trusted By**: The identity of the reviewer who acquired and validated the source must be explicitly declared in the build manifest.

## Rejection of Unofficial Mirrors
Unofficial mirrors, unpinned "latest" branches, and untrusted third-party forks are strictly rejected. We only accept official releases from:
- The kernel.org Git repository (e.g., `https://mirrors.edge.kernel.org/pub/software/scm/git/`)
- The official GitHub release archive.

This prevents supply chain attacks, tampering, and ensures that the build is entirely reproducible.
