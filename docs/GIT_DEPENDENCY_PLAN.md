# Git Dependency Plan

Building a useful local Git and building complete remote-capable Git are
different scopes. Termode will add dependencies in reviewable stages.

## Dependency Roles

- zlib: required for the minimal useful local target
- libcurl: required later for HTTP/HTTPS remote operations
- OpenSSL or another reviewed TLS provider: required with HTTPS support
- expat: include only when selected features require it
- PCRE2: optional depending build configuration
- gettext/iconv: optional localization/compatibility concerns
- Perl: host build prerequisite used by Git's build tooling

Every included dependency needs a version, upstream URL, license, safe source
path, SHA-256 checksum, reviewer identity, and `required_for` stage.

## Stages

### Stage 1: Minimal Local Git

Build enough for `git --version`, `git init`, and `git status`. Start with zlib
and disable optional remote/localization features where the reviewed build
configuration permits it.

### Stage 2: Local Repository Operations

Validate local add, commit, log, branch, and checkout workflows.

### Stage 3: HTTPS Remotes

Add libcurl and a reviewed TLS provider, then test clone/fetch/pull/push.

### Stage 4: Workflow Polish

Add safe credential handling and assess SSH, LFS, submodules, and hooks as
separate capabilities.

Full remote support is intentionally not implied by a successful
`git --version` proof.
