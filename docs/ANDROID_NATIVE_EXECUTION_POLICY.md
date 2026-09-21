# Android Native Execution Policy

Termode never assumes that a writable app-private file becomes executable after
`chmod`. Android may deny execution from that storage even when mode bits look
correct.

For the reviewed v0.64 Git package:

1. The build packages one arm64-v8a ELF under the APK native-library layout.
2. Android extracts it into the app's immutable `nativeLibraryDir`.
3. The platform bridge returns the authoritative directory and exact packaged
   Git path.
4. Dart verifies the manifest strategy, ABI, ELF magic, size, SHA-256, and exact
   approved path.
5. The platform bridge accepts only `--version`, `init`, and `status`,
   requires working directories beneath Termode app files, and supplies a
   controlled HOME, TMPDIR, XDG, PATH, template, and Git-config environment.

Termode does not execute arbitrary paths, files from shared storage, runtime
downloads, writable executable copies, or unreviewed manifest strategies.
Removal deletes the logical prefix mapping and metadata; it never deletes the
APK-owned native payload.
