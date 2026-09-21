# Git On-Device Execution Failure Analysis

## v0.63 symptom

The verified Git 2.44.0 arm64-v8a ELF installed into
`/data/user/0/com.termode.termode/files/usr/bin/git`, but execution returned
`Permission denied`. The installer correctly rolled back.

## Evidence and root cause

The same 5,463,168-byte ELF with the same SHA-256 executed successfully as
`git version 2.44.0` from Android's executable staging area. This ruled out a
bad artifact, wrong ABI, and basic dynamic-linker failure. The failure followed
the destination storage policy: writable app-private files were not an allowed
native execution location on the tested Android 16 device.

## Resolution

v0.64 packages the byte-identical ELF through the Android native-library
mechanism and executes Android's extracted immutable copy. A logical
`TERMODE_PREFIX/usr/bin/git` mapping preserves Termode's prefix model.
Install, verify, version, init, and status now pass on-device.

Failure classification remains explicit: permission/policy, ABI/ELF,
linker/shared-library, PATH/mapping, working directory, HOME/environment, or
unknown. Hardcoded Git output is never substituted.
