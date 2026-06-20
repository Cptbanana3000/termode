Place trusted arm64-v8a Git payload files here.

Expected installable layout:

- bin/git
- lib/... if Git needs private shared libraries
- libexec/... if Git needs helper executables
- share/... for required runtime data

This directory intentionally contains no Git binary in v0.52. Do not replace it
with random binaries. Add files only after provenance, license, ABI, SHA-256,
and `git --version` verification are recorded.
