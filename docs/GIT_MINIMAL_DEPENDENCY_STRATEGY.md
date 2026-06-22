# Git Minimal Dependency Strategy (v0.57)

This document outlines the minimal dependency requirements and scope boundaries for the first Git build target in Termode.

## Stage 1 Git Target (Minimal Local Git)
The first compiled Git artifact aims solely for **local repository basics**:
- `git --version`
- `git init`
- `git status`

Local add/commit/checkout/log operations follow once basic compilation is proved.

## Out of Scope
The following features are **explicitly out of scope** for the Stage 1 artifact and will be introduced in later milestones:
- HTTPS remotes (`clone`, `fetch`, `pull`, `push`)
- SSH protocol remotes
- Git credential helpers
- Git LFS (Large File Storage)
- Git submodules
- Advanced hooks (pre-commit, etc.)
- Full localization/gettext translation

## Dependency Roadmap
To keep the build simple and audited, we categorize dependencies by stage:

| Dependency | Stage / Status | Purpose / Role |
|---|---|---|
| **zlib** | Stage 1 (Required Now) | Compression/decompression of git objects. |
| **Perl** | Stage 1 (Host Prerequisite) | Host-only build prerequisite (used by Git makefiles); **not** bundled into the APK. |
| **libcurl** | Stage 3 (Deferred) | Required for HTTP/HTTPS network operations. |
| **OpenSSL / TLS** | Stage 3 (Deferred) | Required for secure HTTPS transport. |
| **expat** | Stage 4 (Deferred) | Required for HTTP push/fetch (rarely needed for modern workflows; evaluate later). |
| **pcre2** | Stage 4 (Optional) | Perl-compatible regular expressions; evaluate later. |
| **gettext / iconv** | Stage 4 (Deferred) | Avoided for the minimal target to prevent build complexity. |
