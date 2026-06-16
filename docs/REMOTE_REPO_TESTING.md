# Termode Remote Repo Testing

This document describes how to host and test a script-only Termode package
repository.

## Repository Layout

The test repository lives in `termode-test-repo/`:

```text
termode-test-repo/
  index.json
  packages/
    hello-remote.sh
    quote-lite.sh
    device-note.sh
```

Remote packages are scripts only. Do not add native binaries, Python runtimes,
Node.js runtimes, Git package support, or files outside `usr/bin`.

## Index Format

`index.json` uses schema version `1`:

```json
{
  "schemaVersion": 1,
  "name": "Termode Test Repo",
  "updatedAt": "2026-06-17T00:00:00Z",
  "packages": [
    {
      "name": "hello-remote",
      "version": "1.0.0",
      "type": "script",
      "description": "Prints a hello message from the Termode test remote repository.",
      "executable": "hello-remote",
      "files": [
        {
          "path": "usr/bin/hello-remote",
          "url": "packages/hello-remote.sh",
          "sha256": "..."
        }
      ]
    }
  ]
}
```

Each package file URL may be relative to the `index.json` URL. Termode resolves
it before download and only accepts `http` or `https`.

## Calculate SHA-256

On Windows PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 termode-test-repo\packages\hello-remote.sh
```

On Linux/macOS:

```sh
sha256sum termode-test-repo/packages/hello-remote.sh
```

Copy the lowercase hash into the matching file entry in `index.json`.

## Host on GitHub Pages

One simple option is to publish this repo with GitHub Pages:

1. Push `termode-test-repo/` to GitHub.
2. In GitHub, open repository Settings.
3. Open Pages.
4. Set the source to the branch and folder that contains `termode-test-repo/`.
5. Wait for Pages to publish.
6. Use the published index URL:

```text
https://YOUR_USERNAME.github.io/termode/termode-test-repo/index.json
```

If the folder is hosted from a separate repository named `termode-test-repo`,
the URL is usually:

```text
https://YOUR_USERNAME.github.io/termode-test-repo/index.json
```

Any static web server works as long as `index.json` and `packages/*.sh` are
served as plain files.

## Configure Termode

Inside Termode:

```text
pkg repo status
pkg repo set https://YOUR_USERNAME.github.io/termode-test-repo/index.json
pkg repo enable
pkg update
pkg sources
pkg list
pkg info hello-remote
pkg install hello-remote
hello-remote
pkg verify hello-remote
pkg files hello-remote
pkg remove hello-remote
pkg installed
pkg cache clean
```

## Device QA Checklist

Run this sequence on Android after hosting the repo:

```text
pkg repo set <real hosted index URL>
pkg repo enable
pkg update
pkg list
pkg install hello-remote
hello-remote
pkg verify hello-remote
pkg install quote-lite
quote-lite
pkg remove hello-remote
pkg doctor
pkg cache clean
```

Expected results:

- Remote index fetches successfully.
- Remote packages appear in `pkg list`.
- Remote package files install only after SHA-256 verification.
- Remote package commands run immediately in REAL PTY mode.
- Helper reload remains silent.
- `pkg verify` reports `Result: PASS`.
- `pkg remove` removes package files and helper functions cleanly.
- Local fallback still works when the repo is disabled or unreachable.

## Current Limitations

- Remote packages are script-only.
- Package files must install under `usr/bin`.
- Package files must use SHA-256 checksums.
- Package file URLs must resolve to `http` or `https`.
- Remote package signing is not implemented yet.
