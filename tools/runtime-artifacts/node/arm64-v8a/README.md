# Node.js Artifact: arm64-v8a

This directory is reserved for a future trusted `arm64-v8a` Node.js artifact.

Expected layout:

```text
arm64-v8a/
  manifest.json
  files/
    bin/node
```

The Node.js binary foundation uses the Android native library execution pattern (`libtermode_node_exec.so`) located in `applicationInfo.nativeLibraryDir`.

Pre-requisites before bundling:
- trusted source (`termode-built` via nodejs-mobile or standalone cross-compile)
- artifact manifest matching Termode runtime manifest specification
- SHA256 checksums
- Node.js license headers
- verified `node --version` execution
