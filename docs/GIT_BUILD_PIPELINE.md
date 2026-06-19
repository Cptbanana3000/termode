# Git Build Pipeline (v0.47, verified in v0.48, prepared in v0.49, productionized in v0.50)

v0.47 defines the build-side pipeline for a future Git artifact. It does not
build, download, or install Git. v0.48 adds the validation and smoke-test gate
that a future artifact must pass before Termode reports Git as installed. v0.49
adds the arm64-v8a production layout and project-side helper docs/scripts.
v0.50 completes the trusted production pipeline but still ships no payload.

Pipeline stages:

1. Select source
   - Use `termode-built` or `termode-vendored`.
   - Record source URL, version, license, and build method.

2. Build or acquire per ABI
   - Start with `arm64-v8a`.
   - Keep payload files under the runtime prefix layout (`bin/`, `lib/`,
     `libexec/`, `share/`).

3. Generate manifest
   - Use `tools/runtime-artifacts/git/manifest.template.json` as the shape.
   - Write a real `manifest.json` only when payload files exist.

4. Verify checksums
   - SHA-256 is required for every file.
   - The registry rejects missing, malformed, absolute, or traversal paths.

5. Bundle only after validation
   - `RuntimeArtifactRegistryService` remains the trust boundary.
   - `TEMPLATE_ONLY` and `UNAVAILABLE` are not installable.

6. Install and smoke test
   - Install into `TERMODE_PREFIX`.
   - Register the `git` shim.
   - Run `git --version`.
   - Run workspace smoke tests (`git init`, `git status`).

v0.48 checks:

- `git-artifact bundle-status` reports project and bundled artifact readiness.
- `git-artifact bundle-check` validates manifest, ABI, paths, existence, bytes,
  and SHA-256 values without installing.
- `runtime-pkg install git` revalidates, copies only manifest-owned files,
  rechecks copied checksums, runs `git --version`, and rolls back on failure.
- `git-artifact smoke-plan` documents the on-device smoke path.

Release gate:

- Do not announce Git support until `git --version` succeeds on device.
- Missing Git remains an intentional limitation, not an unhealthy app state.

See also [Git arm64-v8a Artifact Pipeline](GIT_ARM64_ARTIFACT_PIPELINE.md),
[Git Artifact Production Status](GIT_ARTIFACT_PRODUCTION_STATUS.md), and
[Git Trusted Build](GIT_TRUSTED_BUILD.md).
