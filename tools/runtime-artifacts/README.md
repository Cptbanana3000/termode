# Termode Runtime Artifacts

This directory is the build-side staging area for trusted runtime artifacts.
It is intentionally empty of executable payloads in v0.47.

Rules:

- Do not place random internet binaries here.
- Do not copy binaries from Termux or another app.
- Do not add archives without a manifest and checksums.
- Do not mark an artifact installable unless it is built or vendored by Termode
  and validated by `RuntimeArtifactRegistryService`.

Current state:

- Git pipeline: present
- Real Git artifact: not bundled
- Runtime install: blocked until a verified artifact exists

See:

- `docs/GIT_ARTIFACT_CONTRACT.md`
- `docs/GIT_ARTIFACT_ACQUISITION.md`
- `docs/GIT_BUILD_PIPELINE.md`
