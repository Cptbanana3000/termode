# npm Runtime Artifact Template

This directory contains the manifest template for npm in Termode.

Expected runtime layout:

```text
tools/runtime-artifacts/npm/
  manifest.template.json
  universal/
    manifest.json
    files/
      bin/npm-cli.js
      lib/node_modules/npm/
```

### Architecture
- npm is a Node.js-driven JavaScript CLI package.
- It is executed by Termode's verified Node.js arm64 runtime (`node bin/npm-cli.js ...`).
- In v0.67, Termode provides:
  1. Pure-Dart local `package.json` creation (`npm init [-y]`).
  2. Scripts execution detection (`npm run <script>`, `npm test`, `npm start`).
  3. Local `node_modules` dependency inspection and tree formatting (`npm ls` / `npm list`).
  4. Environment and Node.js readiness diagnostics (`npm doctor`, `npm-status`, `npm-info`).
  5. Decoupled headless service (`NpmPackageService`) for direct embedding into Calypso IDE.
