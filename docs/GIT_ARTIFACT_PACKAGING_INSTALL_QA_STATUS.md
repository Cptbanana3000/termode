# Git Artifact Packaging / Install QA Status - Termode v0.63

## v0.64 resolution

The v0.63 Path B permission failure is resolved by the native-library-dir
strategy. The exact packaged ELF is executable as the Termode app UID, install
and verify pass, the logical prefix mapping resolves to the approved immutable
backing file, and real version/init/status smoke checks pass. Current status is
Path A; this document otherwise records the v0.63 failure that motivated it.

## Selected path

**Path B: artifact packaging succeeds, while on-device execution verification is blocked.**

The real Git 2.44.0 Android arm64-v8a ELF is packaged and checksum-verified.
The APK installs on an arm64 Android 16 tablet. runtime-pkg validates and copies
the artifact, but the real execution probe returns Permission denied from the
writable app-private files/usr/bin path and rolls the install back.

## Verified host result

- Source: tools/git-build/output/arm64-v8a/git/bin/git
- Manifest: tools/runtime-artifacts/git/arm64-v8a/manifest.json
- Payload: tools/runtime-artifacts/git/arm64-v8a/files/usr/bin/git
- Bytes: 5463168
- SHA-256: 4a4883d3e0b18dc082ac99cdb3da5d80e2b988e2a801b418b0bebfe855a467e1
- Registry state for a matching arm64 device: AVAILABLE
- APK install: PASS
- Exact ELF from Android executable ADB staging: git version 2.44.0 (PASS)
- runtime-pkg install: rolled back after app-private exec Permission denied
- Failure category: permission issue / Android app-private execution policy
- bin-which/git-version/init/status/smoke: blocked because install rolled back

Next milestone if authorization/execution is not completed here:
**v0.64 Git On-Device Execution Fixes**.
