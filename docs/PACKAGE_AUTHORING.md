# Termode Package Authoring

Termode packages are script-only packages installed into the app sandbox. Native binaries, Node.js, Python, Git, npm, root-only commands, and hidden network calls are not supported yet.

Native binary packages are not supported. Both local and remote packages must be `type: script`. Native runtime support is experimental and planned, not available for packages. The bundled runtime proof (the `bundled-runtime-*` commands, see [BUNDLED_RUNTIME_PROOF.md](BUNDLED_RUNTIME_PROOF.md)) is a separate native-bridge proof and is **not** a package mechanism — it is independent of `pkg` and remote repo installs.

The tiny native tools (the `native-tool` commands, see [NATIVE_TOOL_PROOF.md](NATIVE_TOOL_PROOF.md)) are built into Termode and reached through the JNI/native bridge. They are **not** installable packages and cannot be added, removed, or downloaded through `pkg`. Remote packages remain script-only.

Runtime candidate research is the current phase. Node.js, npm, Python, Git, and
native package downloads are not included yet.

`js-proof` is also built into Termode. It is not an installable package and does
not make Node.js or npm available to packages.

`quickjs` is a built-in probe command surface, not an installable package. In
this build QuickJS source is not integrated, Node.js is not available, npm is
not available, and packages cannot use `require`, `import`, `process`, `fs`, or
`http` APIs.

## Package Shape

Each package entry must include:

- `name`: safe package name, such as `note-lite`
- `version`: semantic-ish version string, such as `1.0.0`
- `type`: currently only `script`
- `description`: compact package description
- `executable`: command name exposed in the shell
- `files`: scripts installed under `usr/bin`

Optional fields:

- `category`: for discovery, such as `utility`, `fun`, `text`, `system`, `storage`, or `dev`
- `tags`: list of search terms
- `example`: command shown after install
- `homepage`: project or documentation URL
- `minTermodeVersion`: minimum compatible Termode version

## Local Package Files

Local packages store `files` as a map:

```json
{
  "name": "note-lite",
  "version": "1.0.0",
  "type": "script",
  "description": "Stores small notes.",
  "executable": "note-lite",
  "category": "utility",
  "tags": ["notes", "storage"],
  "example": "note-lite add \"my first note\"",
  "files": {
    "usr/bin/note-lite": "#!/system/bin/sh\n..."
  }
}
```

## Remote Repo Index

Remote packages use `index.json` with file URLs and SHA-256 hashes:

```json
{
  "schemaVersion": 1,
  "packages": [
    {
      "name": "note-lite",
      "version": "1.0.0",
      "type": "script",
      "description": "Stores small notes.",
      "executable": "note-lite",
      "category": "utility",
      "tags": ["notes", "storage"],
      "example": "note-lite add \"my first note\"",
      "files": [
        {
          "path": "usr/bin/note-lite",
          "url": "packages/note-lite.sh",
          "sha256": "<64 hex chars>"
        }
      ]
    }
  ]
}
```

Calculate SHA-256 on Windows:

```powershell
Get-FileHash -Algorithm SHA256 .\packages\note-lite.sh
```

## Safety Rules

Termode only allows managed files under `usr/bin` to prevent path traversal and accidental writes outside the app sandbox. Package scripts should:

- Use POSIX shell syntax compatible with Android `/system/bin/sh`
- Avoid destructive behavior like broad deletes
- Avoid `eval`
- Avoid hidden network calls
- Avoid absolute writes outside Termode app storage
- Avoid root-only commands
- Keep output compact for mobile terminals

Remote repositories must be trusted by the user before use. SHA-256 verifies file integrity, but it does not prove the repo owner is trustworthy.
