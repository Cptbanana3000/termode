# Git Local-Only Limitations - v0.63

## v0.64 support boundary

Local Git support is now claimed for the on-device verified arm64-v8a surface:
`git --version`, `git init`, and `git status`. This does not expand the
remote or advanced feature boundary below.

The packaged Git 2.44.0 binary is intentionally a minimal-local build.
OpenSSL, curl, HTTPS remotes, SSH remotes, credential helpers, Git LFS,
submodules, and remote clone/fetch/pull/push are unsupported and deferred.

Packaging alone does not establish product support. v0.64's support claim is
based on successful real-binary install, version, init, and status checks on
Android. Other ABIs and untested Git commands are not claimed.
