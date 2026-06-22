# Git Source + Dependency Preparation Status (v0.56)

Termode version v0.56 selects **Path B** for its source/dependency preparation.

## Chosen Path: Path B
Source/dependency preparation is completed:
- The target Git version is pinned to `2.44.0`.
- The Git `2.44.0` source archive (`git-2.44.0.tar.xz`) has been downloaded and staged under `tools/git-build/sources/`.
- The zlib `1.3.1` dependency archive (`zlib-1.3.1.tar.xz`) has been downloaded and staged under `tools/git-build/sources/`.
- `build-inputs.json` has been promoted from the candidate template, with the correct target SHA-256 hashes recorded and verified.
- The minimal local Git dependency strategy (Stage 1) is fully verified by host scripts.
- Git remains honestly unavailable within the Android application until a build artifact is produced.

## Staged Status
* **Git Source Staged**: Yes (staged archive: `tools/git-build/sources/git-2.44.0.tar.xz`)
* **Perl Installed**: No (Perl is a host-side build prerequisite only and is missing from the host)
* **zlib Staged**: Yes (staged archive: `tools/git-build/sources/zlib-1.3.1.tar.xz`)
* **Build Inputs Configured**: Yes (`build-inputs.json` promoted with candidate set to false)
* **Git Artifact Staging**: Unavailable

Git is honestly unavailable. No fake Git commands exist. The package installer will safely refuse to install Git until a real validated artifact has been built, verified, and placed in the registry.
