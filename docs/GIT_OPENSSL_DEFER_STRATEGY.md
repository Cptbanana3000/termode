# OpenSSL/Curl Defer Strategy - Termode v0.62

To compile Git for arm64-v8a without introducing complex cross-compilation dependency chains early, we defer both OpenSSL and curl dependencies.

## Rationale
1. **Dependency Complexity**: Staging, configuring, and compiling OpenSSL and curl for Android requires compiling their dependencies, managing version matching, and verifying checksums for both libraries.
2. **First Milestone Objective**: The primary validation target for Git inside Termode is a local-only database. No remote network cloning or push operations are needed for basic initialization and project versioning.
3. **Zlib Sufficiency**: The only compression library needed for local Git is zlib, which is successfully built and verified.
4. **Security Isolation**: By disabling network modules (`NO_CURL`, `NO_OPENSSL`), the generated Git binary is isolated from network activity, lowering the security surface area of the beta package installer.

## Next Steps
Staging OpenSSL and libcurl will be planned for a future milestone (e.g., `v0.65+`) once local execution, packaging, and QA integration of the local Git binary are fully complete.
