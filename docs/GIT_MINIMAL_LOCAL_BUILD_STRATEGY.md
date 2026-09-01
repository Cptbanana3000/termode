# Git Minimal Local Build Strategy - Termode v0.62

To bypass the build blocker for OpenSSL and provide a working Git client on Android, we target a minimal local-only build mode.

## Scope of first target (Local Git)
We limit the capabilities of the first Git binary target to local operations only:
- `git --version`
- `git init`
- `git status`
- Local staging, commits, branches, and diffs.

## Deferred Features (Network & External dependencies)
The following remote and network features are deferred to a later release milestone:
- **HTTPS/HTTP operations** (requires `libcurl` and `openssl` or alternative TLS backend).
- **SSH remotes** (requires `ssh` client wrapper).
- **Credential helpers** (depends on secure hardware/libsecret binding).
- **Git LFS** (requires Golang support).
- **Submodules over network** (requires network functionality).
- **Remote authentication** (credential dialogs/token handling).

## Compilation Strategy
By explicitly disabling the optional modules in Git's Makefile via environment variables, we can construct the binary without the corresponding header files or libraries:
- `NO_OPENSSL=YesPlease`: Disables SSL/TLS crypto features.
- `NO_CURL=YesPlease`: Bypasses compile targets for `git-remote-http`, `git-remote-https`, `git-remote-ftp`, and `git-remote-ftps`.
- `NO_EXPAT=YesPlease`: Bypasses expat dependencies (required only for push/fetch/webDAV).
- `NO_GETTEXT=YesPlease`: Bypasses localization dependencies (uses fallthrough english scheme).
- `NO_ICONV=YesPlease`: Bypasses iconv.h character set translations (safe since Android environment uses UTF-8 natively).

zlib remains the only external library because it is required for file compressing/decompressing objects in the Git object database, and it has already been compiled, validated, and verified at `tools/git-build/output/arm64-v8a/zlib`.
